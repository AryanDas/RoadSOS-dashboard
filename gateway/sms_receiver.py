#!/usr/bin/env python3
"""
RoadSOS SMS Fallback Gateway — sms_receiver.py

A hardware gateway script that interfaces with a physical GSM modem via
serial (RS-232 / USB) to receive and parse SMS distress signals from the
RoadSOS mobile application when HTTP connectivity is unavailable.

Protocol:
  The mobile app sends an SMS in the format:
    LAT:{lat};LON:{lon};SEV:{g_force};MED:{blood_type|allergies}

  Example:
    LAT:28.6139;LON:77.2090;SEV:42.3;MED:O+|None

Usage:
  python sms_receiver.py --port COM3 --baud 9600
  python sms_receiver.py --port /dev/ttyUSB0 --baud 115200

Requirements:
  pip install pyserial
"""

import argparse
import json
import logging
import os
import re
import sys
import time

try:
    import serial
except ImportError:
    print("ERROR: pyserial is required. Install with: pip install pyserial")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"
logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)
logger = logging.getLogger("RoadSOS-Gateway")

DISTRESS_PATTERN = re.compile(
    r"LAT:(?P<lat>-?\d+\.?\d*);"
    r"LON:(?P<lon>-?\d+\.?\d*);"
    r"SEV:(?P<sev>\d+\.?\d*);"
    r"MED:(?P<med>.+)"
)

# ---------------------------------------------------------------------------
# GSM Modem Interface
# ---------------------------------------------------------------------------

class GSMModem:
    """Low-level interface for GSM modem communication via AT commands."""

    def __init__(self, port: str, baud: int = 9600, timeout: float = 3.0):
        self.port = port
        self.baud = baud
        self.timeout = timeout
        self.ser = None

    def connect(self):
        """Opens the serial connection and initialises the modem."""
        logger.info(f"Connecting to GSM modem on {self.port} @ {self.baud} baud...")
        self.ser = serial.Serial(
            port=self.port,
            baudrate=self.baud,
            timeout=self.timeout,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
        )
        time.sleep(2)  # Allow modem to settle

        # Factory reset and echo off
        self._send_at("AT&F")
        self._send_at("ATE0")

        # Set SMS text mode (AT+CMGF=1)
        resp = self._send_at("AT+CMGF=1")
        if "OK" not in resp:
            logger.warning("Modem may not support text mode. Trying PDU mode (AT+CMGF=0)...")
            self._send_at("AT+CMGF=0")

        # Enable SMS notification routing to terminal
        self._send_at("AT+CNMI=2,1,0,0,0")

        logger.info("GSM modem initialized successfully.")

    def _send_at(self, command: str) -> str:
        """Sends an AT command and returns the modem response."""
        if not self.ser or not self.ser.is_open:
            raise ConnectionError("Serial port is not open.")

        logger.debug(f"TX → {command}")
        self.ser.write((command + "\r\n").encode())
        time.sleep(0.5)

        response = ""
        while self.ser.in_waiting > 0:
            response += self.ser.read(self.ser.in_waiting).decode(errors="ignore")
            time.sleep(0.1)

        logger.debug(f"RX ← {response.strip()}")
        return response

    def read_all_sms(self) -> list[dict]:
        """Reads all stored SMS messages from the SIM."""
        raw = self._send_at('AT+CMGL="ALL"')
        messages = []

        lines = raw.strip().split("\n")
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if line.startswith("+CMGL:"):
                # Parse header: +CMGL: <index>,<stat>,<oa>,<alpha>,<scts>
                header = line
                body = lines[i + 1].strip() if (i + 1) < len(lines) else ""
                messages.append({
                    "header": header,
                    "body": body,
                })
                i += 2
            else:
                i += 1

        logger.info(f"Retrieved {len(messages)} SMS message(s) from modem.")
        return messages

    def delete_sms(self, index: int):
        """Deletes an SMS by index."""
        self._send_at(f"AT+CMGD={index}")

    def wait_for_incoming(self) -> str | None:
        """
        Blocks until a +CMTI notification arrives (new SMS received).
        Returns the storage index of the new message.
        """
        logger.info("Listening for incoming SMS distress signals...")
        while True:
            if self.ser and self.ser.in_waiting > 0:
                data = self.ser.read(self.ser.in_waiting).decode(errors="ignore")
                # +CMTI: "SM",<index>
                match = re.search(r'\+CMTI:\s*"[^"]+",\s*(\d+)', data)
                if match:
                    index = int(match.group(1))
                    logger.info(f"📩 New SMS notification received at index {index}.")
                    return self._read_sms_at(index)
            time.sleep(0.5)

    def _read_sms_at(self, index: int) -> str | None:
        """Reads a single SMS at a given index."""
        raw = self._send_at(f'AT+CMGR={index}')
        lines = raw.strip().split("\n")
        for i, line in enumerate(lines):
            if line.strip().startswith("+CMGR:"):
                if (i + 1) < len(lines):
                    return lines[i + 1].strip()
        return None

    def disconnect(self):
        """Closes the serial connection."""
        if self.ser and self.ser.is_open:
            self.ser.close()
            logger.info("GSM modem disconnected.")


# ---------------------------------------------------------------------------
# Distress Signal Parser
# ---------------------------------------------------------------------------

def parse_distress_sms(body: str) -> dict | None:
    """
    Parses a RoadSOS distress SMS payload.

    Expected format:
      LAT:{lat};LON:{lon};SEV:{g_force};MED:{blood_type|allergies}

    Returns a dict with parsed fields, or None if the format doesn't match.
    """
    match = DISTRESS_PATTERN.match(body.strip())
    if not match:
        return None

    med_parts = match.group("med").split("|", 1)

    return {
        "latitude": float(match.group("lat")),
        "longitude": float(match.group("lon")),
        "severity_g_force": float(match.group("sev")),
        "blood_type": med_parts[0] if len(med_parts) > 0 else "Unknown",
        "allergies": med_parts[1] if len(med_parts) > 1 else "None",
        "raw": body.strip(),
    }


# ---------------------------------------------------------------------------
# Alert Dispatcher (extensible hook)
# ---------------------------------------------------------------------------

def dispatch_alert(distress: dict):
    """
    Dispatches a parsed distress signal to the appropriate response system.

    In production, this would:
      - Forward to the RoadSOS backend via HTTP POST
      - Notify nearby ambulances
      - Alert registered emergency contacts
      - Log to a local incident database

    For now, we log the alert and write it to a local JSON file.
    """
    logger.warning(
        f"🚨 DISTRESS SIGNAL RECEIVED:\n"
        f"   Location : ({distress['latitude']}, {distress['longitude']})\n"
        f"   Severity : {distress['severity_g_force']}g\n"
        f"   Blood    : {distress['blood_type']}\n"
        f"   Allergies: {distress['allergies']}"
    )

    # Append to local incidents log
    log_path = "distress_incidents.jsonl"
    with open(log_path, "a") as f:
        f.write(json.dumps(distress) + "\n")
    logger.info(f"Incident logged to {log_path}")


# ---------------------------------------------------------------------------
# Main Loop
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="RoadSOS SMS Fallback Gateway — GSM Modem Listener"
    )
    parser.add_argument(
        "--port",
        type=str,
        default="COM3",
        help="Serial port of the GSM modem (e.g., COM3, /dev/ttyUSB0)",
    )
    parser.add_argument(
        "--baud",
        type=int,
        default=9600,
        help="Baud rate for the serial connection (default: 9600)",
    )
    parser.add_argument(
        "--scan-existing",
        action="store_true",
        help="Scan and process all existing SMS messages on startup",
    )
    args = parser.parse_args()

    modem = GSMModem(port=args.port, baud=args.baud)

    try:
        modem.connect()

        # Optionally process any existing SMS messages
        if args.scan_existing:
            logger.info("Scanning existing SMS messages...")
            existing = modem.read_all_sms()
            for msg in existing:
                distress = parse_distress_sms(msg["body"])
                if distress:
                    dispatch_alert(distress)
                else:
                    logger.debug(f"Non-distress SMS ignored: {msg['body'][:50]}")

        # Enter continuous listening mode
        while True:
            body = modem.wait_for_incoming()
            if body:
                distress = parse_distress_sms(body)
                if distress:
                    dispatch_alert(distress)
                else:
                    logger.info(f"Received non-distress SMS: {body[:80]}")

    except KeyboardInterrupt:
        logger.info("Gateway shutting down (user interrupt).")
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
    finally:
        modem.disconnect()


if __name__ == "__main__":
    main()

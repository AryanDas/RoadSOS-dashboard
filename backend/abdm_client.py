"""
RoadSOS Backend — ABDM Health Facility Registry (HFR) Client

Integrates with the Ayushman Bharat Digital Mission (ABDM) Sandbox to
authenticate and verify hospital operational status via the Health
Facility Registry (HFR) API (Module 2).

ABDM Sandbox Base URL: https://hfr-sandbox.abdm.gov.in
Documentation: https://sandbox.abdm.gov.in/docs/hfr

Authentication Flow:
  1. Obtain a session token from ABDM Gateway using client credentials.
  2. Use the session token to query the HFR search API.
  3. Cross-reference OSM hospital data with HFR records.
"""

import os
import logging
from typing import Optional
import requests

logger = logging.getLogger("roadsos.abdm")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

ABDM_GATEWAY_URL = os.getenv(
    "ABDM_GATEWAY_URL",
    "https://dev.abdm.gov.in/gateway/v0.5"
)
ABDM_HFR_URL = os.getenv(
    "ABDM_HFR_URL",
    "https://hfr-sandbox.abdm.gov.in/api/v1"
)
ABDM_CLIENT_ID = os.getenv("ABDM_CLIENT_ID", "")
ABDM_CLIENT_SECRET = os.getenv("ABDM_CLIENT_SECRET", "")


# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

class ABDMAuthError(Exception):
    """Raised when ABDM authentication fails."""
    pass


def get_abdm_session_token() -> str:
    """
    Obtains a session token from the ABDM Gateway using client credentials.

    Returns:
        A bearer access token string.

    Raises:
        ABDMAuthError: If authentication fails.
    """
    if not ABDM_CLIENT_ID or not ABDM_CLIENT_SECRET:
        raise ABDMAuthError(
            "ABDM_CLIENT_ID and ABDM_CLIENT_SECRET environment variables must be set. "
            "Register at https://sandbox.abdm.gov.in to obtain credentials."
        )

    url = f"{ABDM_GATEWAY_URL}/sessions"
    payload = {
        "clientId": ABDM_CLIENT_ID,
        "clientSecret": ABDM_CLIENT_SECRET,
    }
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    logger.info("Requesting ABDM session token...")

    try:
        response = requests.post(url, json=payload, headers=headers, timeout=15)
        response.raise_for_status()
    except requests.RequestException as e:
        raise ABDMAuthError(f"ABDM Gateway authentication failed: {e}")

    try:
        data = response.json()
    except (ValueError, TypeError) as e:
        raise ABDMAuthError(f"Failed to parse ABDM session token JSON response: {e}")
    token = data.get("accessToken")

    if not token:
        raise ABDMAuthError(f"No accessToken in ABDM response: {data}")

    logger.info("ABDM session token obtained successfully.")
    return token


# ---------------------------------------------------------------------------
# HFR Search & Verification
# ---------------------------------------------------------------------------

def search_facility_by_name(
    facility_name: str,
    state: Optional[str] = None,
    token: Optional[str] = None,
) -> list[dict]:
    """
    Searches the ABDM Health Facility Registry for a facility by name.

    Args:
        facility_name: The name of the hospital to search for.
        state: Optional state filter (e.g., 'Delhi', 'Maharashtra').
        token: ABDM session token. Obtained automatically if not provided.

    Returns:
        A list of matching facility records from HFR.
    """
    if token is None:
        token = get_abdm_session_token()

    url = f"{ABDM_HFR_URL}/facility/search"
    params = {
        "facilityName": facility_name,
    }
    if state:
        params["state"] = state

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }

    logger.info(f"Searching HFR for facility: '{facility_name}'")

    try:
        response = requests.get(url, params=params, headers=headers, timeout=15)
        response.raise_for_status()
    except requests.RequestException as e:
        logger.error(f"HFR search failed: {e}")
        return []

    try:
        data = response.json()
        facilities = data if isinstance(data, list) else data.get("facilities", [])
    except (ValueError, TypeError) as e:
        logger.error(f"Failed to parse HFR search JSON response: {e}")
        return []

    logger.info(f"HFR returned {len(facilities)} result(s) for '{facility_name}'.")
    return facilities


def verify_facility_by_id(
    facility_id: str,
    token: Optional[str] = None,
) -> Optional[dict]:
    """
    Retrieves detailed information about a facility by its HFR Facility ID.

    Args:
        facility_id: The unique ABDM HFR facility identifier.
        token: ABDM session token.

    Returns:
        A dict with facility details, or None if not found.
    """
    if token is None:
        token = get_abdm_session_token()

    url = f"{ABDM_HFR_URL}/facility/{facility_id}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }

    logger.info(f"Verifying HFR facility ID: {facility_id}")

    try:
        response = requests.get(url, headers=headers, timeout=15)
        if response.status_code == 404:
            logger.warning(f"Facility {facility_id} not found in HFR.")
            return None
        response.raise_for_status()
    except requests.RequestException as e:
        logger.error(f"HFR facility verification failed: {e}")
        return None

    try:
        return response.json()
    except (ValueError, TypeError) as e:
        logger.error(f"Failed to parse HFR facility verification JSON response: {e}")
        return None


def cross_verify_hospitals(
    osm_hospitals: list[dict],
    token: Optional[str] = None,
) -> list[dict]:
    """
    Cross-references a list of OSM hospital records against the ABDM HFR
    to verify their operational status.

    For each hospital, we search HFR by name and attach verification metadata:
      - abdm_verified: bool
      - abdm_facility_id: str or None
      - operational_status: str ('Active', 'Inactive', 'Unknown')
      - abdm_data: dict of additional HFR fields

    Args:
        osm_hospitals: List of hospital dicts from Overpass (must have 'name').
        token: ABDM session token. Obtained once and reused.

    Returns:
        The enriched hospital list with ABDM verification fields.
    """
    if token is None:
        try:
            token = get_abdm_session_token()
        except ABDMAuthError as e:
            logger.warning(f"ABDM auth skipped: {e}. Marking all as unverified.")
            for h in osm_hospitals:
                h["abdm_verified"] = False
                h["abdm_facility_id"] = None
                h["operational_status"] = "Unknown"
            return osm_hospitals

    enriched = []
    for hospital in osm_hospitals:
        name = hospital.get("name", "")
        result = {**hospital}

        if not name or name.startswith("Unnamed"):
            result["abdm_verified"] = False
            result["abdm_facility_id"] = None
            result["operational_status"] = "Unknown"
            enriched.append(result)
            continue

        matches = search_facility_by_name(name, token=token)

        if matches:
            best = matches[0]
            result["abdm_verified"] = True
            result["abdm_facility_id"] = best.get("facilityId", best.get("id"))
            result["operational_status"] = best.get(
                "facilityStatus",
                best.get("status", "Active"),
            )
            result["abdm_data"] = {
                "ownership": best.get("ownership"),
                "facility_type": best.get("facilityType"),
                "specialities": best.get("specialities", []),
                "system_of_medicine": best.get("systemOfMedicine"),
                "address": best.get("address"),
            }
        else:
            result["abdm_verified"] = False
            result["abdm_facility_id"] = None
            result["operational_status"] = "Unknown"

        enriched.append(result)

    verified_count = sum(1 for h in enriched if h.get("abdm_verified"))
    logger.info(
        f"ABDM cross-verification complete: "
        f"{verified_count}/{len(enriched)} hospitals verified."
    )

    return enriched

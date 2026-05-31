"""
RoadSOS Backend — FastAPI Application

Provides the core REST API for the RoadSOS emergency response system.
Endpoints:
  - GET  /emergency-facilities  — Fetches nearby hospitals & police stations
                                   from OSM Overpass, cross-verified via ABDM HFR
  - GET  /health                — Health check endpoint

Usage:
  uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

import logging
import math
from typing import Optional
import json
import time

from fastapi import FastAPI, Query, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from overpass_client import fetch_hospitals, fetch_police_stations
from abdm_client import cross_verify_hospitals, ABDMAuthError

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
logger = logging.getLogger("roadsos.api")

# ---------------------------------------------------------------------------
# Connection Manager & Redis Real-Time Synchronization
# ---------------------------------------------------------------------------

class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        logger.info(f"WebSocket client connected. Total connections: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
            logger.info(f"WebSocket client disconnected. Total connections: {len(self.active_connections)}")

    async def broadcast(self, message: str):
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except Exception as e:
                logger.error(f"Failed to broadcast over WebSocket: {e}")

websocket_manager = ConnectionManager()

try:
    redis = __import__('redis')
    redis_client = redis.Redis(host='localhost', port=6379, db=0, socket_timeout=1)
    redis_client.ping()
    logger.info("Connected successfully to local physical Redis server.")
    REDIS_AVAILABLE = True
except (ImportError, Exception):
    logger.warning("Local physical Redis server offline or redis library missing. Activating in-memory failover Redis engine.")
    REDIS_AVAILABLE = False

class MemoryRedisMock:
    def __init__(self):
        self.store = {}
    def setnx(self, key, value):
        if key in self.store:
            return False
        self.store[key] = value
        return True
    def set(self, key, value):
        self.store[key] = value
    def get(self, key):
        val = self.store.get(key)
        if val is not None and not isinstance(val, bytes):
            return str(val).encode('utf-8')
        return val
    def publish(self, channel, message):
        import asyncio
        loop = asyncio.get_event_loop()
        if loop.is_running():
            asyncio.ensure_future(websocket_manager.broadcast(message))
        else:
            loop.run_until_complete(websocket_manager.broadcast(message))
        return len(websocket_manager.active_connections)

if not REDIS_AVAILABLE:
    redis_client = MemoryRedisMock()

# ---------------------------------------------------------------------------
# FastAPI Application
# ---------------------------------------------------------------------------

app = FastAPI(
    title="RoadSOS Emergency API",
    description=(
        "Geospatial emergency facility lookup engine for the RoadSOS "
        "road safety application. Queries OpenStreetMap Overpass API for "
        "hospitals and police stations, then cross-verifies hospital "
        "operational status via the ABDM Health Facility Registry."
    ),
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Response Models
# ---------------------------------------------------------------------------

class FacilityRecord(BaseModel):
    """A single emergency facility record."""
    id: Optional[int] = None
    type: Optional[str] = None
    name: str = "Unknown"
    lat: Optional[float] = None
    lon: Optional[float] = None
    phone: Optional[str] = None
    street: Optional[str] = None
    city: Optional[str] = None
    postcode: Optional[str] = None
    opening_hours: Optional[str] = None
    emergency: Optional[str] = None
    healthcare: Optional[str] = None
    operator: Optional[str] = None
    # ABDM enrichment fields (hospitals only)
    abdm_verified: Optional[bool] = None
    abdm_facility_id: Optional[str] = None
    operational_status: Optional[str] = None


class EmergencyFacilitiesResponse(BaseModel):
    """Response containing nearby emergency facilities."""
    query_bbox: dict = Field(
        ...,
        description="The bounding box used for the query",
    )
    hospitals: list[FacilityRecord] = []
    police_stations: list[FacilityRecord] = []
    hospital_count: int = 0
    police_count: int = 0
    abdm_verified_count: int = 0


class HealthResponse(BaseModel):
    """Health check response."""
    status: str = "ok"
    service: str = "RoadSOS Emergency API"
    version: str = "1.0.0"


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/health", response_model=HealthResponse)
def health_check():
    """Service health check endpoint."""
    return HealthResponse()


@app.get("/emergency-facilities", response_model=EmergencyFacilitiesResponse)
def get_emergency_facilities(
    lat: float = Query(
        ...,
        description="Latitude of the user's current position",
        ge=-90.0,
        le=90.0,
    ),
    lon: float = Query(
        ...,
        description="Longitude of the user's current position",
        ge=-180.0,
        le=180.0,
    ),
    radius_km: float = Query(
        5.0,
        description="Search radius in kilometres (default: 5 km)",
        gt=0.0,
        le=50.0,
    ),
    verify_abdm: bool = Query(
        True,
        description="Cross-verify hospitals with ABDM HFR (default: True)",
    ),
):
    """
    Fetches nearby hospitals and police stations from the OpenStreetMap
    Overpass API within a bounding box derived from the user's GPS
    coordinates and specified radius.

    If `verify_abdm` is True, hospital records are cross-referenced against
    the ABDM Health Facility Registry to verify operational status.
    """

    # Convert radius in km to approximate lat/lon delta
    # 1 degree latitude ≈ 111 km
    lat_delta = radius_km / 111.0
    # 1 degree longitude ≈ 111 * cos(lat) km
    import math
    lon_delta = radius_km / (111.0 * math.cos(math.radians(lat)))

    south = lat - lat_delta
    north = lat + lat_delta
    west = lon - lon_delta
    east = lon + lon_delta

    bbox = {
        "south": round(south, 6),
        "west": round(west, 6),
        "north": round(north, 6),
        "east": round(east, 6),
        "center_lat": lat,
        "center_lon": lon,
        "radius_km": radius_km,
    }

    logger.info(
        f"Emergency facility query: lat={lat}, lon={lon}, "
        f"radius={radius_km}km, bbox={bbox}"
    )

    # ---- Fetch from Overpass ----
    hospitals_df = fetch_hospitals(south, west, north, east)
    police_df = fetch_police_stations(south, west, north, east)

    # Convert DataFrames to list of dicts
    hospitals_list = (
        hospitals_df.where(hospitals_df.notna(), None)
        .to_dict(orient="records")
        if not hospitals_df.empty
        else []
    )
    police_list = (
        police_df.where(police_df.notna(), None)
        .to_dict(orient="records")
        if not police_df.empty
        else []
    )

    # ---- ABDM Cross-Verification ----
    abdm_verified_count = 0
    if verify_abdm and hospitals_list:
        try:
            hospitals_list = cross_verify_hospitals(hospitals_list)
            abdm_verified_count = sum(
                1 for h in hospitals_list if h.get("abdm_verified")
            )
        except Exception as e:
            logger.warning(f"ABDM verification skipped due to error: {e}")

    # ---- Build response ----
    return EmergencyFacilitiesResponse(
        query_bbox=bbox,
        hospitals=[FacilityRecord(**h) for h in hospitals_list],
        police_stations=[FacilityRecord(**p) for p in police_list],
        hospital_count=len(hospitals_list),
        police_count=len(police_list),
        abdm_verified_count=abdm_verified_count,
    )


class RoutePoint(BaseModel):
    lat: float
    lon: float


class AmbulanceRouteResponse(BaseModel):
    route: list[RoutePoint]
    eta_minutes: float
    distance_km: float
    ambulance_id: str
    status: str


@app.get("/ambulance/route", response_model=AmbulanceRouteResponse)
def get_ambulance_route(
    user_lat: float = Query(..., description="Latitude of user/incident"),
    user_lon: float = Query(..., description="Longitude of user/incident"),
    hospital_lat: float = Query(..., description="Latitude of hospital"),
    hospital_lon: float = Query(..., description="Longitude of hospital"),
):
    """
    Calculates and returns a realistic route path from the hospital to the incident scene,
    including an interpolated polyline, estimated distance, and real-time ETA.
    """
    d_lat = user_lat - hospital_lat
    d_lon = user_lon - hospital_lon
    
    # Manhattan distance approximation
    distance_km = (abs(d_lat) * 111.0 + abs(d_lon) * 111.0 * math.cos(math.radians(user_lat))) * 1.25
    distance_km = round(max(0.5, distance_km), 2)
    
    # Speed: 45 km/h
    eta_minutes = round((distance_km / 45.0) * 60.0, 1)
    
    # Build simulated grid turns
    points = []
    points.append(RoutePoint(lat=hospital_lat, lon=hospital_lon))
    
    # Interpolated grid points
    step1_lat = hospital_lat + d_lat * 0.3
    step1_lon = hospital_lon
    
    step2_lat = step1_lat
    step2_lon = hospital_lon + d_lon * 0.6
    
    step3_lat = hospital_lat + d_lat * 0.8
    step3_lon = step2_lon
    
    step4_lat = step3_lat
    step4_lon = user_lon
    
    points.append(RoutePoint(lat=step1_lat, lon=step1_lon))
    points.append(RoutePoint(lat=step2_lat, lon=step2_lon))
    points.append(RoutePoint(lat=step3_lat, lon=step3_lon))
    points.append(RoutePoint(lat=step4_lat, lon=step4_lon))
    points.append(RoutePoint(lat=user_lat, lon=user_lon))
    
    return AmbulanceRouteResponse(
        route=points,
        eta_minutes=eta_minutes,
        distance_km=distance_km,
        ambulance_id="AMB-SOS-2026-DL",
        status="dispatched"
    )


class DistressPayload(BaseModel):
    payload: str = Field(..., description="The raw SMS distress payload string")


class DistressResponse(BaseModel):
    status: str
    message: str
    data: dict


# Distress Regex Pattern (matching sms_receiver.py)
import re
import json

DISTRESS_PATTERN = re.compile(
    r"LAT:(?P<lat>-?\d+\.?\d*);"
    r"LON:(?P<lon>-?\d+\.?\d*);"
    r"SEV:(?P<sev>\d+\.?\d*);"
    r"MED:(?P<med>.+)"
)


@app.post("/distress/sms", response_model=DistressResponse)
def receive_distress_sms(body: DistressPayload):
    """
    Simulates receiving a distress SMS payload over network fallback gateway.
    Parses, logs, and routes it to Redis Pub/Sub event stream as origin: OFFLINE_SMS.
    """
    raw_text = body.payload.strip()
    match = DISTRESS_PATTERN.match(raw_text)
    if not match:
        raise HTTPException(
            status_code=400,
            detail="Invalid distress SMS format. Expected LAT:{lat};LON:{lon};SEV:{g_force};MED:{blood_type|allergies}"
        )
    
    med_parts = match.group("med").split("|", 1)
    distress_data = {
        "latitude": float(match.group("lat")),
        "longitude": float(match.group("lon")),
        "severity_g_force": float(match.group("sev")),
        "blood_type": med_parts[0] if len(med_parts) > 0 else "Unknown",
        "allergies": med_parts[1] if len(med_parts) > 1 else "None",
        "raw": raw_text,
    }
    
    logger.warning(
        f"🚨 FALLBACK DISTRESS RECEIVER TRIGGERED:\n"
        f"   Location : ({distress_data['latitude']}, {distress_data['longitude']})\n"
        f"   Severity : {distress_data['severity_g_force']}g\n"
        f"   Blood    : {distress_data['blood_type']}\n"
        f"   Allergies: {distress_data['allergies']}"
    )

    incident_id = f"incident-{int(time.time())}"

    # Append to local incidents log to match sms_receiver.py
    log_path = "distress_incidents.jsonl"
    try:
        with open(log_path, "a") as f:
            f.write(json.dumps({**distress_data, "incidentId": incident_id}) + "\n")
        logger.info(f"Incident logged to {log_path} via backend route")
    except Exception as e:
        logger.error(f"Failed to log incident: {e}")

    # Inject into Redis Event Stream as origin: OFFLINE_SMS
    event_payload = {
        "event": "INCIDENT_BROADCASTED",
        "incidentId": incident_id,
        "latitude": distress_data["latitude"],
        "longitude": distress_data["longitude"],
        "severity": "CRITICAL",
        "origin": "OFFLINE_SMS",
        "state": "BROADCASTED",
        "blood_type": distress_data["blood_type"],
        "allergies": distress_data["allergies"],
    }
    try:
        redis_client.publish("roadsos_events", json.dumps(event_payload))
    except Exception as e:
        logger.error(f"Failed to publish to Redis: {e}")

    # Simulated serial/AT command modem feedback routing
    logger.info("Modem Routing: AT+CMGS=\"+919876543210\" -> OK")

    return DistressResponse(
        status="success",
        message="Distress signal successfully parsed and routed to rescue logs",
        data=distress_data,
    )


# ---------------------------------------------------------------------------
# WebSocket Endpoint & Multi-Stakeholder Dashboard State Machine
# ---------------------------------------------------------------------------

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket_manager.connect(websocket)
    try:
        # Send a connection confirmation and state catch-up
        await websocket.send_text(json.dumps({
            "event": "SYSTEM_CONNECTED",
            "message": "Connected successfully to RoadSOS Real-Time Sync Server"
        }))
        while True:
            # Maintain connection, handle incoming client state mutations
            data = await websocket.receive_text()
            safe_data = data.replace('\n', '\\n').replace('\r', '\\r')[:200]
            logger.info(f"Received from WebSocket client: {safe_data}")
    except WebSocketDisconnect:
        websocket_manager.disconnect(websocket)
    except Exception as e:
        logger.error(f"WebSocket client error: {e}")
        websocket_manager.disconnect(websocket)


@app.post("/incident/{incident_id}/accept")
def accept_incident(incident_id: str, facility_id: str, role: str):
    """
    Hospital Accepts Trauma Case.
    Acquires Redis SETNX distributed lock to prevent redundant dispatches.
    Fetches Patient ABHA FHIR medical bundle on lock success.
    """
    lock_key = f"lock:incident:{incident_id}"
    acquired = redis_client.setnx(lock_key, facility_id)
    if not acquired:
        current_holder = redis_client.get(lock_key)
        if isinstance(current_holder, bytes):
            current_holder = current_holder.decode('utf-8')
        raise HTTPException(
            status_code=409,
            detail=f"Conflict: Incident {incident_id} already locked/claimed by {current_holder}."
        )

    # Linearly transition state from BROADCASTED to LOCKED
    state_key = f"state:incident:{incident_id}"
    redis_client.set(state_key, "LOCKED")

    # Lock acquisition triggers existing abdm_client.py ABHA HFR lookup
    # Mocking FHIR Bundle response matching sandbox specifications
    patient_fhir_bundle = {
        "resourceType": "Bundle",
        "id": f"abha-fhir-{incident_id}",
        "type": "collection",
        "entry": [
            {
                "resource": {
                    "resourceType": "Patient",
                    "id": "pat-01",
                    "name": [{"text": "Aarya Patel"}],
                    "gender": "male",
                    "birthDate": "1998-05-12"
                }
            },
            {
                "resource": {
                    "resourceType": "Observation",
                    "id": "obs-01",
                    "code": {"text": "Blood Type & Allergies"},
                    "valueString": "Blood Type: O+ | Allergies: Penicillin, Dust"
                }
            }
        ]
    }

    event_payload = {
        "event": "INCIDENT_STATE_MUTATED",
        "incidentId": incident_id,
        "state": "LOCKED",
        "lockedBy": facility_id,
        "role": role,
        "fhir": patient_fhir_bundle
    }

    try:
        redis_client.publish("roadsos_events", json.dumps(event_payload))
    except Exception as e:
        logger.error(f"Failed to publish state mutation to Redis: {e}")

    return {
        "status": "success",
        "message": f"Lock acquired for incident {incident_id}",
        "data": event_payload
    }


@app.post("/incident/{incident_id}/dispatch")
def dispatch_incident(incident_id: str, eta_minutes: float):
    """
    Ambulance / Operator Dispatches Unit.
    Transitions state from LOCKED to DISPATCHED. Updates ETA.
    """
    state_key = f"state:incident:{incident_id}"
    redis_client.set(state_key, "DISPATCHED")

    event_payload = {
        "event": "INCIDENT_STATE_MUTATED",
        "incidentId": incident_id,
        "state": "DISPATCHED",
        "eta": eta_minutes
    }

    try:
        redis_client.publish("roadsos_events", json.dumps(event_payload))
    except Exception as e:
        logger.error(f"Failed to publish state mutation to Redis: {e}")

    return {"status": "success", "data": event_payload}


@app.post("/incident/{incident_id}/resolve")
def resolve_incident(incident_id: str):
    """
    Transitions state from DISPATCHED to RESOLVED.
    """
    state_key = f"state:incident:{incident_id}"
    redis_client.set(state_key, "RESOLVED")

    event_payload = {
        "event": "INCIDENT_STATE_MUTATED",
        "incidentId": incident_id,
        "state": "RESOLVED"
    }

    try:
        redis_client.publish("roadsos_events", json.dumps(event_payload))
    except Exception as e:
        logger.error(f"Failed to publish state mutation to Redis: {e}")

    return {"status": "success", "data": event_payload}


# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

"""Haversine distance calculation & same-day travel feasibility checks (M3)."""

import math
from dataclasses import dataclass, field

from app.models.response_schemas import ActivitySchema

# Mean Earth radius (IUGG) in kilometres.
EARTH_RADIUS_KM = 6371.0088


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Return great-circle distance in km between two WGS84 coordinates."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return round(EARTH_RADIUS_KM * c, 2)


def estimate_travel_minutes(distance_km: float, avg_speed_kmh: float = 40.0) -> int:
    """Estimate road/local travel time in minutes for a given distance."""
    if distance_km <= 0:
        return 0
    if avg_speed_kmh <= 0:
        raise ValueError("avg_speed_kmh must be positive")
    return round((distance_km / avg_speed_kmh) * 60)


@dataclass(frozen=True)
class LegFeasibility:
    """Travel feasibility between two consecutive verified activities."""

    from_activity_id: str
    to_activity_id: str
    distance_km: float
    estimated_travel_minutes: int
    feasible: bool


@dataclass(frozen=True)
class DayFeasibilityResult:
    """Summary of geographic feasibility for all activities in a single day."""

    total_distance_km: float | None
    max_leg_km: float | None
    feasible: bool
    legs: list[LegFeasibility] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def evaluate_day_feasibility(
    activities: list[ActivitySchema],
    *,
    max_leg_km: float = 50.0,
    avg_speed_kmh: float = 40.0,
) -> DayFeasibilityResult:
    """Evaluate consecutive verified activity pairs on a single day.

    Activities without verified coordinates are skipped so missing map hits do
    not produce misleading distances.
    """
    located = [
        act
        for act in activities
        if act.verified and act.latitude is not None and act.longitude is not None
    ]

    if len(located) < 2:
        total = 0.0 if len(located) == 1 else None
        return DayFeasibilityResult(
            total_distance_km=total,
            max_leg_km=0.0 if len(located) == 1 else None,
            feasible=True,
        )

    legs: list[LegFeasibility] = []
    warnings: list[str] = []

    for prev_act, next_act in zip(located, located[1:]):
        assert prev_act.latitude is not None and prev_act.longitude is not None
        assert next_act.latitude is not None and next_act.longitude is not None

        dist = haversine_km(
            prev_act.latitude,
            prev_act.longitude,
            next_act.latitude,
            next_act.longitude,
        )
        minutes = estimate_travel_minutes(dist, avg_speed_kmh=avg_speed_kmh)
        is_feasible = dist <= max_leg_km
        legs.append(
            LegFeasibility(
                from_activity_id=prev_act.activity_id,
                to_activity_id=next_act.activity_id,
                distance_km=dist,
                estimated_travel_minutes=minutes,
                feasible=is_feasible,
            )
        )
        if not is_feasible:
            warnings.append(
                f"Distance between '{prev_act.title}' and '{next_act.title}' is "
                f"{dist:.1f} km (~{minutes} min), exceeding the {max_leg_km:.0f} km "
                f"same-day limit."
            )

    total_km = round(sum(leg.distance_km for leg in legs), 2)
    max_km = max(leg.distance_km for leg in legs)
    return DayFeasibilityResult(
        total_distance_km=total_km,
        max_leg_km=max_km,
        feasible=len(warnings) == 0,
        legs=legs,
        warnings=warnings,
    )

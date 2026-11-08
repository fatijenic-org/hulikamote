from fastapi import APIRouter

import demerit_points
from store import get_approved_violations

router = APIRouter(prefix="/demerit", tags=["demerit"])


@router.get("")
async def standings():
    """Every plate with at least one confirmed violation, most points first."""
    return {"plates": demerit_points.tally(await get_approved_violations())}


@router.get("/{plate}")
async def one_plate(plate: str):
    """One plate's points, a per-violation breakdown and its confirmed tickets (0 points if it has none)."""
    return demerit_points.for_plate(await get_approved_violations(), plate)

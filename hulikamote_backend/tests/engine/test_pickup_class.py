"""
The "pickup" vehicle class: judged like the other vehicles, but a pickup is NOT a truck (a truck ban must not ticket it).
Synthetic traffic only.
"""
from types import SimpleNamespace

from engine import lane_signs, privacy
from engine.specialist_jobs import CabinJob
from engine.violations import REGISTRY, VEHICLE_CLASSES
from engine.violations.illegal_loading import IllegalLoading
from engine.violations.no_seatbelt import NoSeatbelt
from engine.violations.passenger_outside import BED_CLASSES
from engine.violations.truck_ban import TruckBan
from tests.engine.test_whole_frame_rules import run_scene, zone_of


def test_a_pickup_is_a_vehicle_everywhere_vehicles_are_listed():
    assert "pickup" in VEHICLE_CLASSES and "pickup" in privacy.VEHICLES and "pickup" in lane_signs.VEHICLE_TYPES
    assert "pickup" in BED_CLASSES                                     # its open back is judged for passengers


def test_a_truck_ban_does_not_ticket_a_pickup_but_still_tickets_a_truck():
    path = [(200 + 9 * i, 500) for i in range(40)]
    zone = zone_of("truck_ban")
    assert zone["banned_classes"] == ["truck"] and TruckBan.banned_default == ("truck",)
    assert run_scene({1: ("truck", lambda i: path[i])}, 40, REGISTRY["truck_ban"], zone)
    assert not run_scene({1: ("pickup", lambda i: path[i])}, 40, REGISTRY["truck_ban"], zone)


def test_loading_is_judged_for_heavy_vehicles_only_by_default():
    assert "pickup" not in IllegalLoading.default_classes
    assert zone_of("illegal_loading")["classes"] == ["bus", "jeepney", "tricycle", "truck"]


def test_a_pickup_driver_needs_a_seatbelt_like_a_car_and_a_truck():
    assert "pickup" in NoSeatbelt.JUDGED_CLASSES
    job = CabinJob()
    for cls, wanted in (("car", True), ("truck", True), ("pickup", True), ("bus", False), ("tricycle", False), ("motorcycle", False)):
        assert job.wanted(["no_seatbelt"], SimpleNamespace(cls=cls)) is wanted


def test_a_lane_sign_treats_a_pickup_as_its_own_type():
    assert "pickup" in lane_signs.SIGNS["no_trucks"]["allowed"]          # a no-trucks sign does not stop pickups
    assert "pickup" not in lane_signs.SIGNS["bus_only"]["allowed"]       # a bus lane does
    assert all(set(spec["allowed"]) <= set(lane_signs.VEHICLE_TYPES) for spec in lane_signs.SIGNS.values())

"""Hazard listing and removal for signed-in users.

A hazard leaves the map in one of three ways:

  * its reporter removes it
  * a township account removes it
  * three different accounts say it is no longer there

Votes need an account precisely so that "three people" means three people. The
reporter cannot vote on their own hazard — they can simply remove it.
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

import auth
import storage

router = APIRouter(prefix="/api/v1/hazards", tags=["Hazards"])

STATUSES = {"ACTIVE", "IN_PROGRESS", "RESOLVED"}


def to_app(report, votes, user):
    count, mine = votes.get(report["id"], (0, False))
    return {
        "id": report["id"],
        "report_type": report["report_type"],
        "severity": report["severity"],
        "road_status": report["road_status"],
        "utility_lines_involved": bool(report["utility_lines_involved"]),
        "description": report["description"],
        "municipality": report["municipality"],
        "address": report["address"],
        "zipcode": report["zipcode"],
        "latitude": report["latitude"],
        "longitude": report["longitude"],
        "status": report["status"],
        "upvotes": report["upvotes"],
        "created_at": report["created_at"],
        "updated_at": report["updated_at"],
        "not_there_votes": count,
        "not_there_threshold": storage.NOT_THERE_THRESHOLD,
        "i_voted_not_there": mine,
        # The owner's identity is never sent — only whether it is the caller.
        "is_mine": bool(user and report.get("owner_id") == user["id"]),
    }


def existing(hazard_id):
    report = storage.get(hazard_id)
    if report is None:
        raise HTTPException(status_code=404, detail="That hazard is no longer on the map.")
    return report


@router.get("")
def list_hazards(user=Depends(auth.optional_user)):
    votes = storage.vote_summary(user["id"] if user else None)
    return [to_app(r, votes, user) for r in storage.query()]


@router.post("/{hazard_id}/not-there")
def vote_not_there(hazard_id: str, user=Depends(auth.require_user)):
    report = existing(hazard_id)
    if report.get("owner_id") == user["id"]:
        raise HTTPException(status_code=400, detail="You reported this hazard — remove it instead of voting.")
    count = storage.add_not_there_vote(hazard_id, user["id"])
    removed = count >= storage.NOT_THERE_THRESHOLD
    if removed:
        storage.remove(hazard_id, reason="community")
    return {"removed": removed, "not_there_votes": count, "not_there_threshold": storage.NOT_THERE_THRESHOLD}


@router.delete("/{hazard_id}")
def remove_hazard(hazard_id: str, user=Depends(auth.require_user)):
    report = existing(hazard_id)
    if user["role"] == "township":
        reason = "township"
    elif report.get("owner_id") == user["id"]:
        reason = "reporter"
    else:
        raise HTTPException(status_code=403, detail="Only the person who reported this, or a township account, can remove it.")
    storage.remove(hazard_id, reason=reason, removed_by=user["id"])
    return {"removed": True}


class StatusChange(BaseModel):
    status: str


@router.patch("/{hazard_id}/status")
def change_status(hazard_id: str, body: StatusChange, user=Depends(auth.require_user)):
    existing(hazard_id)
    if user["role"] != "township":
        raise HTTPException(status_code=403, detail="Only township accounts can change crew status.")
    if body.status not in STATUSES:
        raise HTTPException(status_code=400, detail="Unknown status.")
    report = storage.set_status(hazard_id, body.status)
    return to_app(report, storage.vote_summary(user["id"]), user)

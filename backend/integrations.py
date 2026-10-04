"""Outbound hand-offs to municipal public works desks.

When a report is filed, a structured incident card is forwarded to the town
whose ZIP code it falls in — to a webhook (Zapier, Make, a Cartegraph or
Cityworks intake, anything that accepts JSON) and/or by email.

Nothing is forwarded unless that town has been configured in
`dispatch_config.json`. There are deliberately no built-in destinations: a relay
that mails strangers' reports to a real DPW inbox the town never agreed to is
spam, however well meant. A town opts in by giving you an address.

Safeguards against flooding a desk:
  * duplicates near an open report become confirmations, not new tickets
    (see storage.find_duplicate), so they never reach this module twice
  * `min_severity` drops low-priority reports
  * `max_per_hour` caps what any one town receives
"""

import json
import logging
import os

import httpx

import storage

log = logging.getLogger("stormwatch.dispatch")

CONFIG_PATH = os.environ.get(
    "DISPATCH_CONFIG", os.path.join(os.path.dirname(__file__), "dispatch_config.json")
)
SEVERITY_RANK = {"LOW": 0, "MODERATE": 1, "IMPASSABLE": 2}


def load_config():
    """Re-read on each dispatch so a town can be added without a restart."""
    try:
        with open(CONFIG_PATH) as handle:
            return json.load(handle)
    except FileNotFoundError:
        return {"towns": {}}
    except json.JSONDecodeError as exc:
        log.error("dispatch_config.json is not valid JSON: %s", exc)
        return {"towns": {}}


def maps_link(report):
    # Google's documented cross-platform Maps URL for a search pin.
    return f"https://www.google.com/maps/search/?api=1&query={report['latitude']},{report['longitude']}"


def incident_card(report):
    """The payload a DPW desk receives."""
    return {
        "source": "StormWatch NJ Civic Network",
        "ticket_id": report["id"],
        "ticket_type": report["report_type"],
        "severity": report["severity"],
        "road_status": report["road_status"],
        "utility_lines_involved": bool(report["utility_lines_involved"]),
        "description": report["description"],
        "address": report.get("address"),
        "municipality": report.get("municipality"),
        "zipcode": report.get("zipcode"),
        "latitude": report["latitude"],
        "longitude": report["longitude"],
        "coordinates": f"{report['latitude']},{report['longitude']}",
        "map_url": maps_link(report),
        "photo": report.get("media_url"),
        "confirmations": report["upvotes"],
        "reported_at": report["created_at"],
        # Said plainly so a dispatcher weighs it correctly.
        "verification": "Unverified resident report, triaged by software. Confirm on site.",
    }


def email_text(card):
    lines = [
        f"{card['ticket_type'].replace('_', ' ').title()} — {card['severity']}",
        "",
        card["description"],
        "",
        f"Road status: {card['road_status'].replace('_', ' ').lower()}",
        f"Location: {card['address'] or card['municipality'] or 'see coordinates'}",
        f"GPS: {card['coordinates']}",
        f"Map: {card['map_url']}",
        f"Confirmations: {card['confirmations']}",
        f"Reported: {card['reported_at']}",
    ]
    if card["utility_lines_involved"]:
        lines += ["", "UTILITY LINES INVOLVED — treat as energized; utility must clear before crews approach."]
    lines += ["", card["verification"], f"Ticket {card['ticket_id']} · StormWatch NJ"]
    return "\n".join(lines)


async def send_webhook(url, card):
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(url, json=card)
        response.raise_for_status()


async def send_email(to_address, card):
    """Sends through Resend. Skipped, not failed, when no key is configured."""
    api_key = os.environ.get("RESEND_API_KEY")
    sender = os.environ.get("DISPATCH_FROM_EMAIL")
    if not api_key or not sender:
        return "skipped: RESEND_API_KEY / DISPATCH_FROM_EMAIL not set"
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "from": sender,
                "to": [to_address],
                "subject": f"[StormWatch NJ] {card['ticket_type'].replace('_', ' ').title()} — {card['severity']}",
                "text": email_text(card),
            },
        )
        response.raise_for_status()
    return "sent"


async def forward_to_agency_dispatch(report_id):
    """Background task: route one stored report to its town. Never raises."""
    report = storage.get(report_id)
    if report is None:
        return {"status": "NOT_FOUND"}

    config = load_config()
    town = config.get("towns", {}).get(report.get("zipcode") or "")
    if not town:
        log.info("No dispatch destination for ZIP %s; report %s kept in feed only.",
                 report.get("zipcode"), report_id)
        return {"status": "NO_DESTINATION"}

    minimum = config.get("min_severity", "LOW")
    if SEVERITY_RANK.get(report["severity"], 0) < SEVERITY_RANK.get(minimum, 0):
        return {"status": "BELOW_MIN_SEVERITY"}

    cap = config.get("max_per_hour", 20)
    if storage.dispatches_in_last_hour(report["zipcode"]) >= cap:
        log.warning("Hourly dispatch cap (%s) reached for ZIP %s; report %s held.",
                    cap, report["zipcode"], report_id)
        return {"status": "RATE_LIMITED"}

    card = incident_card(report)
    results = {}
    if town.get("webhook_url"):
        try:
            await send_webhook(town["webhook_url"], card)
            results["webhook"] = "sent"
        except Exception as exc:  # a town's endpoint being down must not break intake
            log.error("Webhook to %s failed: %s", town.get("name"), exc)
            results["webhook"] = f"failed: {exc}"
    if town.get("email"):
        try:
            results["email"] = await send_email(town["email"], card)
        except Exception as exc:
            log.error("Email to %s failed: %s", town.get("name"), exc)
            results["email"] = f"failed: {exc}"

    if "sent" in results.values():
        storage.mark_dispatched(report_id)
    return {"status": "DISPATCHED" if "sent" in results.values() else "FAILED", "results": results}

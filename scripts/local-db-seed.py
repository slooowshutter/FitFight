# Fake fights for `scripts/run-simulator.sh local-db`, made through the same API the app uses: Alex creates two
# fights, the others accept, and everyone syncs six days of steps. Steps count only for people already in a
# live fight, so the order matters. Safe to run again. Prints Alex's session for the app.
import json
import os
import urllib.request
import uuid
from datetime import datetime, time, timedelta, timezone


def call(url, body, headers):
    request = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json", **headers})
    return json.load(urllib.request.urlopen(request))


def api(name, path, body, headers={}):
    return call(f"{os.environ['SERVER']}/api/v1/{path}", body,
                {"Authorization": f"Bearer {sessions[name]['access_token']}", **headers})


sessions = {
    name: call(f"{os.environ['API_URL']}/auth/v1/token?grant_type=password",
               {"email": f"{name}@fitfight.local", "password": "local-dev-only"}, {"apikey": os.environ["KEY"]})
    for name in ["alex", "leo", "nina", "sam"]
}
now = datetime.now(timezone.utc).replace(microsecond=0)
today = datetime.combine(now.date(), time(), timezone.utc)

existing = {fight["name"]: fight["id"] for fight in api("alex", "fights/snapshot", {"time_zone": "UTC"})["fights"]}
for name, started, days, rivals, stake in [
    ("Alex vs Leo", 3, 7, ["leo"], {"stakeKind": "bragging"}),
    ("Office stairs", 5, 14, ["leo", "nina", "sam"], {"stakeKind": "action", "actionText": "buys the coffee"}),
]:
    starts = today - timedelta(days=started)
    fight_id = existing.get(name) or api("alex", "fights", {
        "name": name, "startsAt": starts.isoformat(), "endsAt": (starts + timedelta(days=days)).isoformat(),
        "timeZone": "UTC", "outcomeRule": "highest_total", "inviteHandles": rivals, "recurring": False, **stake,
    }, {"Idempotency-Key": str(uuid.uuid4())})["id"]
    # Accepting again is a no-op, so a run that stopped halfway finishes the roster.
    for rival in rivals:
        api(rival, f"fights/{fight_id}/accept", {})

# Each phone sends its daily totals plus one total per fight window; fights score from the window totals.
# Alex wins the duel and is second in the group, so both winning and losing screens show.
for name, daily in {"alex": 9000, "leo": 8000, "nina": 11000, "sam": 6000}.items():
    steps = {today - timedelta(days=back): daily + back * 300 for back in range(6)}
    fights = api(name, "fights/snapshot", {"time_zone": "UTC"})["fights"]
    api(name, "healthkit/steps", {
        "complete_through": now.isoformat(), "time_zone": "UTC",
        "merged_days": [{"day": day.date().isoformat(), "starts_at": day.isoformat(),
                         "ends_at": min(day + timedelta(days=1), now).isoformat(), "steps": count}
                        for day, count in steps.items()],
        "fight_aggregates": [{"fight_id": fight["id"], "starts_at": fight["starts_at"], "ends_at": fight["ends_at"],
                              "cutoff_at": now.isoformat(),
                              "steps": sum(count for day, count in steps.items()
                                           if day >= datetime.fromisoformat(fight["starts_at"]))}
                             for fight in fights],
    })

print(sessions["alex"]["access_token"], sessions["alex"]["refresh_token"])

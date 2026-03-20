# scripts/cost-tracker.py — Fetch API provider costs and write JSON summary.
# Called by systemd timer (cost-tracker.nix). Reads provider config from
# COST_TRACKER_CONFIG env var, writes JSON to COST_TRACKER_OUTPUT.
import json
import os
import sys
import time
import urllib.request
import urllib.parse
import urllib.error
from datetime import datetime, timedelta, timezone


def read_key(path):
    with open(path) as f:
        return f.read().strip()


PERIODS = [
    ("cost_24h", 1),
    ("cost_7d", 7),
    ("cost_30d", 30),
    ("cost_365d", 365),
]


def fetch_anthropic_period(key, days):
    now = datetime.now(timezone.utc)
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    start = today - timedelta(days=days)
    # Anthropic max 31 buckets per request; paginate if needed
    total_cost = 0.0
    cursor = start
    while cursor < today:
        chunk_end = min(cursor + timedelta(days=31), today)
        url = (
            "https://api.anthropic.com/v1/organizations/cost_report?"
            "starting_at={}&ending_at={}&bucket_width=1d"
        ).format(
            cursor.strftime("%Y-%m-%dT%H:%M:%SZ"),
            chunk_end.strftime("%Y-%m-%dT%H:%M:%SZ"),
        )
        req = urllib.request.Request(url)
        req.add_header("x-api-key", key)
        req.add_header("anthropic-version", "2023-06-01")
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
        for bucket in data.get("data", []):
            for result in bucket.get("results", []):
                total_cost += float(result.get("amount", 0))
        cursor = chunk_end
        if cursor < today:
            time.sleep(1)  # rate limit courtesy
    # Anthropic returns cents
    return round(total_cost / 100, 2)


def fetch_anthropic_all(key):
    # ~2 years back; older than most accounts
    return fetch_anthropic_period(key, 730)


def fetch_anthropic(key, extra):
    usage = {}
    for period_key, days in PERIODS:
        try:
            usage[period_key] = fetch_anthropic_period(key, days)
        except Exception as exc:
            usage[period_key] = 0
            usage["error_" + period_key] = str(exc)
        time.sleep(2)
    try:
        usage["cost_all"] = fetch_anthropic_all(key)
    except Exception as exc:
        usage["cost_all"] = 0
        usage["error_all"] = str(exc)
    usage["total_cost"] = usage.get("cost_24h", 0)
    return usage


def openai_cost_query(key, start_ts, extra):
    params = {
        "start_time": str(start_ts),
        "bucket_width": "1d",
        "limit": "100",
    }
    # Filter by project IDs if configured
    proj_ids = extra.get("project_ids", "")
    url = "https://api.openai.com/v1/organization/costs?" + urllib.parse.urlencode(params)
    if proj_ids:
        for pid in proj_ids.split(","):
            url += "&project_ids[]=" + pid.strip()
    total = 0.0
    while url:
        req = urllib.request.Request(url)
        req.add_header("Authorization", "Bearer " + key)
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
        for bucket in data.get("data", []):
            for result in bucket.get("results", []):
                amt = result.get("amount", {})
                total += float(amt.get("value", 0))
        if data.get("has_more") and data.get("next_page"):
            base = url.split("&page=")[0].split("?page=")[0]
            url = base + "&page=" + data["next_page"]
        else:
            url = None
    return round(total, 2)


def fetch_openai(key, extra):
    now = datetime.now(timezone.utc)
    usage = {}
    for period_key, days in PERIODS:
        try:
            since = now - timedelta(days=days)
            usage[period_key] = openai_cost_query(
                key, int(since.timestamp()), extra
            )
        except Exception as exc:
            usage[period_key] = 0
            usage["error_" + period_key] = str(exc)
    try:
        # All time: 2 years back
        since_all = now - timedelta(days=730)
        usage["cost_all"] = openai_cost_query(
            key, int(since_all.timestamp()), extra
        )
    except Exception as exc:
        usage["cost_all"] = 0
        usage["error_all"] = str(exc)
    usage["total_cost"] = usage.get("cost_24h", 0)
    return usage


FETCHERS = {
    "anthropic": fetch_anthropic,
    "openai": fetch_openai,
}

LABELS = {
    "anthropic": "Anthropic",
    "openai": "OpenAI",
}


def main():
    config_path = os.environ.get("COST_TRACKER_CONFIG")
    output_path = os.environ.get(
        "COST_TRACKER_OUTPUT", "/run/tsurf-cost.json"
    )
    if not config_path:
        print("COST_TRACKER_CONFIG not set", file=sys.stderr)
        sys.exit(1)

    with open(config_path) as f:
        providers = json.loads(f.read())

    now = datetime.now(timezone.utc)
    instances = []

    for name, pcfg in sorted(providers.items()):
        ptype = pcfg["type"]
        label = LABELS.get(ptype, name)
        try:
            key = read_key(pcfg["key_file"])
            fetcher = FETCHERS.get(ptype)
            if not fetcher:
                instances.append({
                    "user": label,
                    "usage": {"error": "unknown type: " + ptype},
                })
                continue
            usage = fetcher(key, pcfg.get("extraConfig", {}))
            instances.append({"user": label, "usage": usage})
        except Exception as exc:
            instances.append({
                "user": label,
                "usage": {
                    "total_cost": 0,
                    "error": str(exc),
                },
            })

    payload = {
        "instances": instances,
        "as_of": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    tmp = output_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f)
    os.rename(tmp, output_path)
    print(
        "Wrote {} providers to {}".format(len(instances), output_path)
    )


if __name__ == "__main__":
    main()

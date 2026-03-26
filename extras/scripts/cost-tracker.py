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
    """Fetch Anthropic costs for a given number of days back."""
    now = datetime.now(timezone.utc)
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    start = today - timedelta(days=days)
    # Anthropic allows max 31 buckets per request; paginate in 31-day chunks
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
    # Anthropic returns cents; convert to dollars
    return round(total_cost / 100, 2)


def openai_cost_query(key, start_ts, extra):
    """Fetch OpenAI costs from a given start timestamp."""
    params = {
        "start_time": str(start_ts),
        "bucket_width": "1d",
        "limit": "100",
    }
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
            parsed = urllib.parse.urlparse(url)
            base_params = urllib.parse.parse_qs(parsed.query)
            base_params.pop("page", None)
            new_query = urllib.parse.urlencode(base_params, doseq=True)
            url = urllib.parse.urlunparse(parsed._replace(query=new_query))
            url += "&page=" + data["next_page"]
        else:
            url = None
    return round(total, 2)


def fetch_all_periods(period_fetcher, extra):
    """Generic period fetcher — calls period_fetcher(days, extra) for each period + 730d total."""
    usage = {}
    for period_key, days in PERIODS:
        try:
            usage[period_key] = period_fetcher(days, extra)
        except Exception as exc:
            usage[period_key] = 0
            usage["error_" + period_key] = str(exc)
        time.sleep(2)
    try:
        usage["cost_730d"] = period_fetcher(730, extra)
    except Exception as exc:
        usage["cost_730d"] = 0
        usage["error_730d"] = str(exc)
    usage["total_cost"] = usage.get("cost_730d", 0)
    return usage


def fetch_anthropic(key, extra):
    return fetch_all_periods(lambda days, _: fetch_anthropic_period(key, days), extra)


def fetch_openai(key, extra):
    now = datetime.now(timezone.utc)
    return fetch_all_periods(
        lambda days, ex: openai_cost_query(key, int((now - timedelta(days=days)).timestamp()), ex),
        extra,
    )


FETCHERS = {
    "anthropic": fetch_anthropic,
    "openai": fetch_openai,
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
        label = pcfg.get("label", name)
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

#!/usr/bin/env python3
"""Deterministic v2 minute-log simulator and edge-case generator for P04 testing."""

import argparse
import json
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List


def build_minute_log(
    *,
    device_id: str = "sim-v2-01",
    deployment_id: str = "dep-sim-01",
    boot_id: str = "boot-sim-0001",
    window_sequence: int = 1,
    interval_start: datetime | None = None,
    tip_count_start: int = 0,
    tip_count_end: int = 0,
    clock_synchronized: bool = True,
    uptime_start_ms: int = 0,
    temp_avg: float = 28.5,
    humi_avg: float = 70.0,
    wind_avg: float = 2.1,
    calibration_version: str = "rain-bucket-v1",
) -> Dict[str, Any]:
    start_dt = interval_start or datetime(2026, 11, 26, 12, 0, 0, tzinfo=timezone.utc)
    end_dt = start_dt + timedelta(seconds=60)

    payload: Dict[str, Any] = {
        "schema_version": 2,
        "type": "minute_log",
        "device_id": device_id,
        "deployment_id": deployment_id,
        "boot_id": boot_id,
        "window_sequence": window_sequence,
        "clock_quality": "synchronized" if clock_synchronized else "unsynchronized",
        "metrics": {
            "temperature": {
                "unit": "degC",
                "sum": round(temp_avg * 24, 2),
                "count": 24,
                "min": round(temp_avg - 0.5, 2),
                "max": round(temp_avg + 0.5, 2),
                "latest": temp_avg,
            },
            "humidity": {
                "unit": "percent_rh",
                "sum": round(humi_avg * 24, 2),
                "count": 24,
                "min": round(humi_avg - 2.0, 2),
                "max": round(humi_avg + 2.0, 2),
                "latest": humi_avg,
            },
            "wind_speed": {
                "unit": "m/s",
                "sum": round(wind_avg * 12, 2),
                "count": 12,
                "min": max(0.0, round(wind_avg - 0.5, 2)),
                "max": round(wind_avg + 0.8, 2),
                "latest": wind_avg,
            },
        },
        "rain": {
            "counter_epoch": f"{boot_id}:reset-0",
            "calibration_version": calibration_version,
            "tip_count_start": tip_count_start,
            "tip_count_end": tip_count_end,
        },
        "quality": {
            "dht_expected_count": 24,
            "dht_valid_count": 24,
            "wind_expected_count": 12,
            "wind_valid_count": 12,
            "coverage_ms": 60000,
            "rain_coverage_ms": 60000,
        },
    }

    if clock_synchronized:
        payload["interval_start"] = start_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        payload["interval_end"] = end_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    else:
        payload["uptime_start_ms"] = uptime_start_ms
        payload["uptime_end_ms"] = uptime_start_ms + 60000

    return payload


def generate_test_scenarios(device_id: str = "sim-v2-01") -> List[Dict[str, Any]]:
    base = build_minute_log(device_id=device_id, window_sequence=1, tip_count_start=10, tip_count_end=12)
    duplicate = json.loads(json.dumps(base))

    conflict = json.loads(json.dumps(base))
    conflict["metrics"]["temperature"]["sum"] = 999.0

    out_of_order = build_minute_log(device_id=device_id, window_sequence=3, tip_count_start=14, tip_count_end=14)
    unsync = build_minute_log(
        device_id=device_id,
        window_sequence=2,
        clock_synchronized=False,
        uptime_start_ms=120000,
        tip_count_start=12,
        tip_count_end=14,
    )
    counter_decrease = build_minute_log(device_id=device_id, window_sequence=4, tip_count_start=14, tip_count_end=13)
    oversized = build_minute_log(device_id=device_id, window_sequence=5)
    oversized["padding"] = "x" * 9000

    return [
        {"name": "valid", "topic": f"adht/weather/{device_id}/telemetry/log", "payload": base},
        {"name": "duplicate", "topic": f"adht/weather/{device_id}/telemetry/log", "payload": duplicate},
        {"name": "conflict", "topic": f"adht/weather/{device_id}/telemetry/log", "payload": conflict},
        {"name": "out_of_order", "topic": f"adht/weather/{device_id}/telemetry/log", "payload": out_of_order},
        {"name": "unsynchronized", "topic": f"adht/weather/{device_id}/telemetry/log", "payload": unsync},
        {"name": "counter_decrease", "topic": f"adht/weather/{device_id}/telemetry/log", "payload": counter_decrease},
        {"name": "oversized", "topic": f"adht/weather/{device_id}/telemetry/log", "payload": oversized},
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate P04 v2 telemetry test scenarios")
    parser.add_argument("--device-id", default="sim-v2-01")
    args = parser.parse_args()
    for item in generate_test_scenarios(args.device_id):
        print(json.dumps(item))


if __name__ == "__main__":
    main()

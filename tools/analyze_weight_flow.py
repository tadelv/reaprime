#!/usr/bin/env python3

import argparse
import csv
import json
import math
import statistics
import urllib.request
from datetime import datetime
from pathlib import Path
from xml.sax.saxutils import escape


def parse_timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def extract_samples(shot):
    samples = []
    for measurement in shot.get("measurements", []):
        scale = measurement.get("scale")
        if not scale or not isinstance(scale.get("weightFlow"), (int, float)):
            continue
        samples.append(
            {
                "timestamp": parse_timestamp(scale["timestamp"]),
                "weight": float(scale["weight"]),
                "flow": float(scale["weightFlow"]),
            }
        )
    return samples


def longest_active_run(samples, minimum_flow=0.1):
    runs = []
    current = []
    for sample in samples:
        if sample["flow"] > minimum_flow:
            current.append(sample)
        elif current:
            runs.append(current)
            current = []
    if current:
        runs.append(current)
    return max(runs, key=len, default=[])


def metrics(samples, minimum_flow=0.1):
    intervals = [
        (right["timestamp"] - left["timestamp"]).total_seconds()
        for left, right in zip(samples, samples[1:])
        if right["timestamp"] > left["timestamp"]
    ]
    active = longest_active_run(samples, minimum_flow)
    flows = [sample["flow"] for sample in active]
    deltas = [abs(right - left) for left, right in zip(flows, flows[1:])]
    second_deltas = [
        abs(flows[index] - 2 * flows[index - 1] + flows[index - 2])
        for index in range(2, len(flows))
    ]
    tail = flows[-10:]
    tail_deltas = [abs(right - left) for left, right in zip(tail, tail[1:])]
    return {
        "samples": len(samples),
        "active_samples": len(active),
        "cadence_hz": 1 / statistics.median(intervals) if intervals else 0.0,
        "mean_abs_delta": statistics.fmean(deltas) if deltas else 0.0,
        "tail_mean_abs_delta": statistics.fmean(tail_deltas)
        if tail_deltas
        else 0.0,
        "p95_abs_delta": sorted(deltas)[math.ceil(len(deltas) * 0.95) - 1]
        if deltas
        else 0.0,
        "mean_abs_second_delta": statistics.fmean(second_deltas)
        if second_deltas
        else 0.0,
    }


def write_csv(path, samples):
    start = samples[0]["timestamp"] if samples else None
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["timestamp", "elapsed_seconds", "weight_g", "flow_g_s"])
        for sample in samples:
            elapsed = (sample["timestamp"] - start).total_seconds()
            writer.writerow(
                [sample["timestamp"].isoformat(), elapsed, sample["weight"], sample["flow"]]
            )


def write_svg(path, samples, title):
    width, height, margin = 1000, 420, 50
    if samples:
        start = samples[0]["timestamp"]
        xs = [(sample["timestamp"] - start).total_seconds() for sample in samples]
        ys = [sample["flow"] for sample in samples]
    else:
        xs, ys = [0.0], [0.0]
    x_span = max(xs[-1] - xs[0], 1.0)
    y_min, y_max = min(ys), max(ys)
    y_span = max(y_max - y_min, 1.0)
    points = " ".join(
        f"{margin + (x - xs[0]) / x_span * (width - 2 * margin):.1f},"
        f"{height - margin - (y - y_min) / y_span * (height - 2 * margin):.1f}"
        for x, y in zip(xs, ys)
    )
    path.write_text(
        f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<rect width="100%" height="100%" fill="white"/>
<text x="{margin}" y="28" font-family="sans-serif" font-size="18">{escape(title)}</text>
<line x1="{margin}" y1="{height - margin}" x2="{width - margin}" y2="{height - margin}" stroke="#777"/>
<line x1="{margin}" y1="{margin}" x2="{margin}" y2="{height - margin}" stroke="#777"/>
<polyline fill="none" stroke="#1976d2" stroke-width="2" points="{points}"/>
<text x="{width / 2}" y="{height - 12}" text-anchor="middle" font-family="sans-serif">seconds</text>
<text x="14" y="{height / 2}" transform="rotate(-90 14 {height / 2})" text-anchor="middle" font-family="sans-serif">flow (g/s)</text>
<text x="{margin}" y="{height - margin + 20}" font-family="sans-serif" font-size="12">0</text>
<text x="{width - margin}" y="{height - margin + 20}" text-anchor="end" font-family="sans-serif" font-size="12">{x_span:.1f}</text>
<text x="{margin - 8}" y="{height - margin}" text-anchor="end" font-family="sans-serif" font-size="12">{y_min:.2f}</text>
<text x="{margin - 8}" y="{margin + 4}" text-anchor="end" font-family="sans-serif" font-size="12">{y_max:.2f}</text>
</svg>
'''
    )


def fetch_shot(base_url, shot_id):
    url = f"{base_url.rstrip('/')}/api/v1/shots/{shot_id}"
    with urllib.request.urlopen(url, timeout=15) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("shot_ids", nargs="+")
    parser.add_argument("--base-url", default="http://192.168.12.57:8080")
    parser.add_argument("--output-dir", type=Path, default=Path("flow-analysis"))
    parser.add_argument("--min-flow", type=float, default=0.1)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    for shot_id in args.shot_ids:
        shot = fetch_shot(args.base_url, shot_id)
        samples = extract_samples(shot)
        result = metrics(samples, args.min_flow)
        write_csv(args.output_dir / f"{shot_id}.csv", samples)
        write_svg(args.output_dir / f"{shot_id}.svg", samples, shot_id)
        print(
            f"{shot_id}: samples={result['samples']} active={result['active_samples']} "
            f"cadence={result['cadence_hz']:.2f}Hz "
            f"mean|Δflow|={result['mean_abs_delta']:.3f}g/s "
            f"tail10={result['tail_mean_abs_delta']:.3f}g/s "
            f"p95|Δflow|={result['p95_abs_delta']:.3f}g/s "
            f"mean|Δ²flow|={result['mean_abs_second_delta']:.3f}g/s"
        )


if __name__ == "__main__":
    main()

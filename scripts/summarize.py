#!/usr/bin/env python3
"""Turn the raw output of vm-run.sh into recording-sheet rows (median of the runs).

  python3 summarize.py results/              one row per test and phase
  python3 summarize.py results/ --compare    before / after / delta per test and metric
  python3 summarize.py results/ --csv out.csv

Reads results/t<NN>-<phase>-run<k>-tcp.json, -udp.json (iperf3 -J) and -sockperf.txt.
Gbps comes from the TCP run (received), Mpps and loss from the 64-byte UDP run (received packets
per second), p50/p99 from the sockperf summary lines "percentile 50.000" and "percentile 99.000".
vmkernel network CPU and pNIC drops come from the host captures and are filled in by hand.
"""
import argparse, csv, json, re, statistics, sys
from collections import defaultdict
from pathlib import Path

NAME = re.compile(r"t(\d+)-(before|after)-run(\d+)-(tcp\.json|udp\.json|sockperf\.txt)$")
PCT = {50: re.compile(r"percentile\s+50\.000\s*=\s*([\d.]+)"),
       99: re.compile(r"percentile\s+99\.000\s*=\s*([\d.]+)")}


def tcp_gbps(path):
    end = json.loads(path.read_text())["end"]
    return end["sum_received"]["bits_per_second"] / 1e9


def udp_mpps_loss(path):
    s = json.loads(path.read_text())["end"]["sum"]
    received = s["packets"] - s["lost_packets"]
    return received / s["seconds"] / 1e6, s["lost_percent"]


def sockperf_p50_p99(path):
    text = path.read_text(errors="replace")
    out = []
    for p in (50, 99):
        m = PCT[p].findall(text)
        out.append(float(m[-1]) if m else None)
    return tuple(out)


def med(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None


def collect(folder):
    raw = defaultdict(lambda: defaultdict(list))  # (test, phase) -> metric -> [values]
    for f in sorted(Path(folder).iterdir()):
        m = NAME.match(f.name)
        if not m:
            continue
        key = (int(m.group(1)), m.group(2))
        try:
            if m.group(4) == "tcp.json":
                raw[key]["gbps"].append(tcp_gbps(f))
            elif m.group(4) == "udp.json":
                mpps, loss = udp_mpps_loss(f)
                raw[key]["mpps"].append(mpps)
                raw[key]["loss"].append(loss)
            else:
                p50, p99 = sockperf_p50_p99(f)
                raw[key]["p50"].append(p50)
                raw[key]["p99"].append(p99)
        except (KeyError, ValueError, json.JSONDecodeError) as e:
            print(f"skipped {f.name}: {e}", file=sys.stderr)
    return {k: {m: med(v) for m, v in metrics.items()} | {"runs": max(len(v) for v in metrics.values())}
            for k, metrics in raw.items() if any(metrics.values())}


def fmt(v, digits=2):
    return "" if v is None else f"{v:.{digits}f}"


def lat(r):
    if r.get("p50") is None and r.get("p99") is None:
        return ""
    return f"{fmt(r.get('p50'), 0)} / {fmt(r.get('p99'), 0)}"


def sheet_rows(data):
    rows = [["Test", "Phase", "Runs", "Gbps", "Mpps (64 B)", "Loss %", "p50 / p99 us"]]
    for (t, phase) in sorted(data, key=lambda k: (k[0], k[1] != "before")):
        r = data[(t, phase)]
        rows.append([t, phase, r["runs"], fmt(r.get("gbps")), fmt(r.get("mpps"), 3),
                     fmt(r.get("loss")), lat(r)])
    return rows


def compare_rows(data):
    rows = [["Test", "Metric", "Before", "After", "Delta %"]]
    metrics = [("gbps", "Throughput (Gbps)", 2), ("mpps", "pps at 64 B (Mpps)", 3),
               ("loss", "UDP loss (%)", 2), ("p50", "Latency p50 (us)", 0), ("p99", "Latency p99 (us)", 0)]
    for t in sorted({k[0] for k in data}):
        b, a = data.get((t, "before"), {}), data.get((t, "after"), {})
        for key, label, d in metrics:
            vb, va = b.get(key), a.get(key)
            if vb is None and va is None:
                continue
            delta = f"{(va - vb) / vb * 100:+.1f}" if vb not in (None, 0) and va is not None else ""
            rows.append([t, label, fmt(vb, d), fmt(va, d), delta])
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", help="folder written by vm-run.sh (default name: results)")
    ap.add_argument("--compare", action="store_true", help="before / after / delta instead of the sheet")
    ap.add_argument("--csv", metavar="FILE", help="also write the table to a CSV file")
    args = ap.parse_args()

    data = collect(args.folder)
    if not data:
        sys.exit(f"no t<NN>-<phase>-run<k>-* files in {args.folder}")
    rows = compare_rows(data) if args.compare else sheet_rows(data)

    widths = [max(len(str(r[i])) for r in rows) for i in range(len(rows[0]))]
    for r in rows:
        print("  ".join(str(c).ljust(w) for c, w in zip(r, widths)))
    if args.csv:
        with open(args.csv, "w", newline="") as fh:
            csv.writer(fh).writerows(rows)
        print(f"written to {args.csv}")


if __name__ == "__main__":
    main()

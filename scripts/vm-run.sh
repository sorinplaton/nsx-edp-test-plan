#!/usr/bin/env bash
# Section 2 row 0, the standard run, from the client VM (Linux, iperf3 3.9+, sockperf).
# Start `iperf3 -s` and `sockperf server` on the server side first, then:
#   ./vm-run.sh <test#> <before|after> <server-ip> [runs]      (runs defaults to 3)
# Each run: TCP throughput (iperf3 -P 4 -t 60), 64-byte UDP pps (iperf3 -u -b 0 -l 64 -P 4 -t 60),
# and latency (sockperf ping-pong -t 30 --full-rtt). iperf3 output is saved as JSON so that
# summarize.py can read it. Files: results/t<NN>-<phase>-run<k>-{tcp.json,udp.json,sockperf.txt}
set -euo pipefail

[ $# -ge 3 ] || { echo "usage: $0 <test#> <before|after> <server-ip> [runs]"; exit 1; }
T=$(printf '%02d' "$1"); PHASE=$2; IP=$3; RUNS=${4:-3}
case $PHASE in before|after) ;; *) echo "phase must be before or after"; exit 1;; esac
command -v iperf3 >/dev/null || { echo "iperf3 not found"; exit 1; }
command -v sockperf >/dev/null || { echo "sockperf not found"; exit 1; }

OUT=${OUT:-results}; mkdir -p "$OUT"
echo "test $T, $PHASE, server $IP, $RUNS runs, $(date -Is), client $(hostname)" | tee -a "$OUT/runs.log"

for k in $(seq 1 "$RUNS"); do
  P="$OUT/t$T-$PHASE-run$k"
  echo "[run $k/$RUNS] TCP";      iperf3 -c "$IP" -P 4 -t 60 -J > "$P-tcp.json"
  sleep 5
  echo "[run $k/$RUNS] UDP 64B";  iperf3 -c "$IP" -u -b 0 -l 64 -P 4 -t 60 -J > "$P-udp.json"
  sleep 5
  echo "[run $k/$RUNS] sockperf"; sockperf ping-pong -i "$IP" -t 30 --full-rtt > "$P-sockperf.txt" 2>&1
  sleep 5
done
echo "done. Summarise with: python3 summarize.py $OUT"

#!/bin/sh
# Section 2 host-side capture for one test run. Start it on each ESXi host in the path just before the
# client VM starts vm-run.sh:
#   sh esxi-capture.sh <test#> <before|after> [vmnic ...]
# It records esxtop in batch mode (5 s samples, 60 samples), net-stats, and the pNIC counters of the
# listed vmnics before and after the run. Files are named t<NN>-<phase>-<host>-*.
# Read-only: it changes nothing on the host.

[ $# -ge 2 ] || { echo "usage: $0 <test#> <before|after> [vmnic ...]"; exit 1; }
T=$(printf '%02d' "$1"); PHASE=$2; shift 2
HOST=$(hostname -s 2>/dev/null || hostname)
P="t$T-$PHASE-$HOST"
NICS=${*:-$(esxcli network nic list | awk 'NR>2 && $1 ~ /^vmnic/ {print $1}')}

for n in $NICS; do esxcli network nic stats get -n "$n" > "$P-nicstats-$n-start.txt" 2>&1; done

esxtop -b -d 5 -n 60 > "$P.csv" 2>"$P-esxtop.err" &
ESXTOP=$!
net-stats -A -t WwQqihVvc > "$P-netstats.txt" 2>&1

echo "esxtop running (pid $ESXTOP, about 5 min); waiting for it to finish..."
wait $ESXTOP

for n in $NICS; do esxcli network nic stats get -n "$n" > "$P-nicstats-$n-end.txt" 2>&1; done
echo "saved: $(ls "$P"* | tr '\n' ' ')"

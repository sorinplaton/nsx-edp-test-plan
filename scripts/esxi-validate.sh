#!/bin/sh
# Section 4 post-enable validation, host side. Run on each ESXi host after it is realized in the new mode,
# before taking it out of maintenance mode, and again after the soak:
#   sh esxi-validate.sh [tep-vmk] [peer-tep-ip]
# With a TEP vmk and a peer TEP address it also sends the 8972-byte DF ping.
# Read-only: it changes nothing on the host.

HOST=$(hostname -s 2>/dev/null || hostname)
OUT=validate-$HOST-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT" || exit 1

run() {
  f=$1; shift
  echo "## $*" > "$OUT/$f"
  "$@" >> "$OUT/$f" 2>&1 || echo "(exit $?)" >> "$OUT/$f"
}

# the mode actually took
run host-switch.txt        nsxcli -c "get host-switch"
run ens-switch-list.txt    nsxdp-cli ens switch list
run ens-port-list.txt      nsxdp-cli ens port list
run ens-uplink-list.txt    nsxdp-cli ens uplink list
run ens-stats.txt          nsxdp-cli ens stats get
run ens-flowtable.txt      nsxdp-cli ens flow-table stats get
run ens-flowdump.txt       nsxdp-cli ens flow-table dump
run esxcfg-nics-e.txt      esxcfg-nics -e

# transport node health
run tn-status.txt          nsxcli -c "get transport-node status"
run bfd-sessions.txt       nsxcli -c "get bfd-sessions"
run tunnel-ports.txt       nsxcli -c "get tunnel-ports"

# MTU and offloads
if [ -n "$1" ] && [ -n "$2" ]; then
  run vmkping-8972.txt     vmkping -I "$1" -d -s 8972 -c 5 "$2"
fi
for n in $(esxcli network nic list | awk 'NR>2 && $1 ~ /^vmnic/ {print $1}'); do
  run "nic-get-$n.txt"     esxcli network nic get -n "$n"
  run "nic-stats-$n.txt"   esxcli network nic stats get -n "$n"
done

# ENS or driver resets
run vmkernel-ens.txt       sh -c 'grep -iE "ens|reset" /var/log/vmkernel.log | tail -200'

echo "saved in $OUT"
echo "--- uplinks in ENS mode (every NSX uplink should be listed):"
cat "$OUT/ens-uplink-list.txt"

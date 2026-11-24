#!/bin/sh
# Section 1 pre-checks, ESXi side. Run on each host over SSH before touching the TNP:
#   sh esxi-precheck.sh [outdir]
# Saves NIC, driver, firmware, VIB, VDS, NSX host switch, LACP and vmk output into one folder per host.
# Read-only: it changes nothing on the host.

HOST=$(hostname -s 2>/dev/null || hostname)
OUT=${1:-precheck-$HOST-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT" || exit 1

run() {  # run <file> <command...>: save the output, keep going on error
  f=$1; shift
  echo "## $*" > "$OUT/$f"
  "$@" >> "$OUT/$f" 2>&1 || echo "(exit $?)" >> "$OUT/$f"
}

run nic-list.txt            esxcli network nic list
for n in $(esxcli network nic list | awk 'NR>2 {print $1}'); do
  run "nic-get-$n.txt"      esxcli network nic get -n "$n"
done
run vib-drivers.txt         sh -c 'esxcli software vib list | grep -iE "nmlx5|icen|i40en|ixgben|bnxtnet"'
run dvs-list.txt            esxcli network vswitch dvs vmware list
run lacp-status.txt         esxcli network vswitch dvs vmware lacp status get
run vmk-list.txt            esxcli network ip interface list
run nsx-host-switch.txt     nsxcli -c "get host-switch"
run esxcfg-nics-e.txt       esxcfg-nics -e

echo "saved in $OUT"
echo "ENS capability per vmnic (also check the Physical Adapters tab in NSX):"
grep -iE "vmnic|ENS Capable" "$OUT/esxcfg-nics-e.txt" 2>/dev/null | head -40

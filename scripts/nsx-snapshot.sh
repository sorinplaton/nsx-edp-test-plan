#!/usr/bin/env bash
# Section 1 configuration snapshot, NSX side (read-only GETs only):
#   ./nsx-snapshot.sh            asks for the NSX Manager, user and password (hidden, never saved)
# Saves every host Transport Node Profile (your rollback copy), the transport node collections, and per
# host transport node: its host switch mode, realized state and the raw capabilities answer.
set -euo pipefail
command -v jq >/dev/null || { echo "jq not found"; exit 1; }

read -rp  "NSX Manager FQDN or IP: " NSX
read -rp  "NSX user [admin]: " NSX_USER; NSX_USER=${NSX_USER:-admin}
read -rsp "NSX password: " NSX_PASS; echo
EP=/policy/api/v1/infra/sites/default/enforcement-points/default
nsx() { curl -sfk -u "$NSX_USER:$NSX_PASS" -H 'Content-Type: application/json' "$@"; }

OUT=nsx-snapshot-$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
nsx "https://$NSX/policy/api/v1/infra/host-transport-node-profiles" > "$OUT/tnp-all.json"
nsx "https://$NSX$EP/transport-node-collections"                    > "$OUT/tnc-all.json"
nsx "https://$NSX$EP/host-transport-nodes"                          > "$OUT/tn-all.json"

printf '%-36s %-16s %s\n' HOST MODE STATE | tee "$OUT/summary.txt"
jq -r '.results[] | [.id, .display_name, .host_switch_spec.host_switches[0].host_switch_mode] | @tsv' \
  "$OUT/tn-all.json" | while IFS=$'\t' read -r id name mode; do
  state=$(nsx "https://$NSX$EP/host-transport-nodes/$id/state" | tee "$OUT/tn-$name-state.json" | jq -r .state) || state="?"
  # raw ENS capability answer, compare with the Physical Adapters tab in the NSX UI
  nsx "https://$NSX/api/v1/transport-nodes/$id/capabilities" > "$OUT/tn-$name-capabilities.json" || true
  printf '%-36s %-16s %s\n' "$name" "$mode" "$state" | tee -a "$OUT/summary.txt"
done
echo "saved in $OUT (tnp-all.json is the rollback copy)"

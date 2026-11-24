# NSX Enhanced Datapath: test plan and scripts

A before/after test plan for moving an NSX cluster to Enhanced Datapath (EDP), with scripts that run the
same commands each time and turn the raw output into a recording sheet.

The point is to show what EDP changes with numbers: CPU per Gbps and pps with small packets. Large-packet
throughput between two VMs barely moves, so a plain iperf run tends to say "EDP did nothing" when the gain is
in vmkernel network CPU and 64-byte packet rate.

How to enable EDP and change modes one host at a time, in the UI and with the API, is in the blog post
[NSX Enhanced Datapath: what it is, how to enable it, how to change modes](https://sorinplaton.github.io/posts/nsx-edp-performance-per-host/)
([in French](https://sorinplaton.github.io/fr/posts/nsx-edp-performance-per-host/)).

## The plan

[TEST-PLAN.md](TEST-PLAN.md) has five sections:

1. **Pre-checks:** NIC, driver and firmware against the Broadcom Compatibility Guide, ENS capability per
   uplink, driver VIB versions, the vCenter vMotion setting, and a snapshot and clone of the TNP.
2. **Baseline:** twelve tests (0 to 11) run before and after, from VM to VM on one host up to Edge failover
   under load. Each test runs three times for 60 s and the median is kept.
3. **Enable:** host by host in maintenance mode, one hop per mode change (a direct Standard to Performance
   change is rejected with error 9544), from the UI or the NSX Policy API, then the cloned TNP on the cluster.
4. **Post-enable validation:** the mode really took (ENS switch, uplinks, flow table), transport node health,
   functional regression, and a soak.
5. **Compare:** before, after and delta per path.

The plan covers EDP Standard (`ENS_INTERRUPT`) and EDP Performance (`ENS`), with the same method as the blog
post: one host at a time in maintenance mode, through EDP Standard, and the cloned TNP attached to the cluster
at the end. For Performance, keep a separate results folder per mode, for example
`OUT=results-edp-std ./vm-run.sh 1 after <ip>` and `OUT=results-edp-perf ./vm-run.sh 1 after <ip>`.

## Layout

| Path | What it is | Where it runs |
|---|---|---|
| `TEST-PLAN.md` | The full plan | |
| `scripts/esxi-precheck.sh` | Section 1: NIC, driver, VIB, VDS, NSX host switch, LACP and vmk output, saved per host | ESXi host (SSH) |
| `scripts/nsx-snapshot.sh` | Section 1: every TNP (rollback copy), transport node collections, mode and state per host | Any Linux/macOS host with `curl` and `jq` |
| `scripts/vm-run.sh` | Section 2, row 0: TCP throughput, 64-byte UDP pps and sockperf latency, three runs | Client VM (Linux, iperf3 3.9+, sockperf) |
| `scripts/esxi-capture.sh` | Section 2: esxtop batch, net-stats and pNIC counters for one run | Each ESXi host in the path (SSH) |
| `scripts/summarize.py` | Medians per test and phase, or a before/after/delta table | Wherever the results folder is (Python 3.9+) |
| `scripts/esxi-validate.sh` | Section 4: ENS switch, uplinks, flow table, BFD, tunnels, DF ping, offloads, vmkernel.log | ESXi host (SSH) |
| `sheets/recording-sheet.csv` | One line per test per phase | |
| `sheets/compare.csv` | Before / after / delta per path and metric | |
| `tools/edp_per_host.py` | Changes the host switch mode one host at a time, through EDP Standard (see the blog post) | Any host with `pip install pyvmomi requests` |

The ESXi scripts are plain `sh` and only read: copy them to the host (for example to `/tmp`) and run them
with `sh`. The NSX scripts only send GET requests and ask for the password, which is never stored.

## A run, in short

```bash
# before: on each host in the path (SSH), then on the client VM
sh esxi-capture.sh 1 before vmnic1 vmnic2     # ESXi host A
./vm-run.sh 1 before 192.168.50.12            # client VM, server VM runs iperf3 -s and sockperf server

# enable EDP (section 3), validate (section 4), then the same commands with "after"
sh esxi-validate.sh vmk10 172.16.50.12        # ESXi host, TEP vmk and a peer TEP
./vm-run.sh 1 after 192.168.50.12

python3 summarize.py results --compare        # before / after / delta for the iperf3 and sockperf metrics
```

vmkernel network CPU, pNIC drops and the Edge and failover numbers come from the host and Edge captures and
go into the sheets by hand.

## Status

- `summarize.py` was checked against sample iperf3 (`-J`) and sockperf output.
- The shell scripts pass a syntax check (`sh -n`, `bash -n`) but have not yet run against a lab.
- `edp_per_host.py` was used in a nested NSX 4.2.4 lab to change modes in both directions. Nested numbers say
  nothing about performance, so that lab only checks that the procedure works.

Open an issue if a command behaves differently on your NSX or ESX build.

## Licence

MIT, see [LICENSE](LICENSE).

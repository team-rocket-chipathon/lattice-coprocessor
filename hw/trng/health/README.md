# hw/trng/health — health monitors

NIST SP 800-90B continuous health tests for the entropy source.

| File | Issue | What |
|------|-------|------|
| `rct_monitor.sv` | #8 | Repetition Count Test — flags a stuck source (same value `CUTOFF` times in a row). |

Parameters: `WIDTH` (bits per sample), `CUTOFF` (the NIST cutoff C, `1 + ceil(-log2(alpha)/H_min)`).

## Test (cocotb + Verilator)
```bash
source /home/esarkar/myenv/bin/activate
cd hw/trng/health/test && make            # or: make SIM_BUILD=/tmp/rct_sim_build on the FUSE mount
```
Covers: stuck source alarms exactly at `CUTOFF` repeats, varying streams never alarm, a run just below cutoff stays quiet.

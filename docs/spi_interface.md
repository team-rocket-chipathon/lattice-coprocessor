# SPI Subordinate Interface — Proposal

**Issue:** #11 Design register-mapped SPI controller
**Owner:** Sarkar
**Status:** 🟡 PROPOSAL — needs sign-off from @infinitymdm (keccak) and @rahulearn2019 (health)

This document is the *contract* for the SPI block. It defines every wire that
crosses the block boundary so the SPI RTL can be written and tested against
stubs **before** the keccak core and health monitor exist. Once Marcus and Rahul
approve the signal names/widths, this becomes the spec.

---

## 1. Where SPI sits

SPI is the chip's only external register interface. It does **not** touch the
ring oscillators, entropy pooling, or LDO — those are upstream. SPI only talks to
the two blocks that produce *outputs*:

```
  off-chip master                SPI SUBORDINATE                 on-chip blocks
  ───────────────                ───────────────                 ──────────────
  SCLK ───────────────▶┌───────────────────────┐
  MOSI ───────────────▶│                         │◀── rng_data[7:0] ──┐
  MISO ◀───────────────│   register-mapped       │    rng_valid       │ KECCAK CORE
  nCS  ───────────────▶│   SPI subordinate       │──▶ rng_pop ────────┘ (Marcus)
                        │                         │
  clk  ───────────────▶│                         │──▶ ctrl_* ─────────▶ (keccak control)
  rst_n ──────────────▶│                         │
                        │                         │◀── health_status ──┐ HEALTH MON
                        │                         │◀── alarm ──────────┘ (Rahul)
                        └───────────────────────┘
```

---

## 2. Top-level ports

### Clock / reset (digital domain)

| Signal  | Dir | Width | Notes |
|---------|-----|-------|-------|
| `clk`   | in  | 1     | System clock. SPI lines are oversampled in this domain. |
| `rst_n` | in  | 1     | Active-low synchronous-deassert reset. |

### SPI pins (asynchronous, from off-chip master — SPI mode 0)

| Signal | Dir | Width | Notes |
|--------|-----|-------|-------|
| `sclk` | in  | 1     | SPI clock from master. Oversampled, not used as a clock. |
| `mosi` | in  | 1     | Master-out / subordinate-in (COPI). |
| `miso` | out | 1     | Master-in / subordinate-out (CIPO). Valid only while selected. |
| `ncs`  | in  | 1     | Active-low chip select. Idles high. |

### Data plane — random bytes from keccak (consult @infinitymdm)

| Signal      | Dir | Width | Notes |
|-------------|-----|-------|-------|
| `rng_data`  | in  | `RNG_W` (8) | Head of the keccak output FIFO. Width is a parameter; SPI reads return the low 8 bits. |
| `rng_valid` | in  | 1     | 1 = a byte is available to read. |
| `rng_pop`   | out | 1     | 1-clk pulse: advance the FIFO after a `RNG_DATA` read completes. |

### Status plane — health monitor (consult @rahulearn2019)

| Signal          | Dir | Width | Notes |
|-----------------|-----|-------|-------|
| `health_status` | in  | `HEALTH_W` (8) | One bit per statistical test (see §5). Width is a parameter; SPI reads return the low 8 bits. |
| `alarm`         | in  | 1     | 1 = entropy irregularity (mirrors the `ALARM` chip pin). |

### Control plane — to keccak (consult @infinitymdm)

| Signal          | Dir | Width | Notes |
|-----------------|-----|-------|-------|
| `ctrl_enable`   | out | 1     | Level. 1 = keccak running. |
| `ctrl_mode`     | out | 1     | 0 = SHA-3 conditioning, 1 = SHAKE-128 expand. |
| `ctrl_reseed`   | out | 1     | 1-clk pulse: request reseed / restart. |
| `ctrl_soft_rst` | out | 1     | 1-clk pulse: soft reset of the keccak datapath. |

> Control signal set is a starting proposal — trim/extend to match the real
> keccak core once Marcus defines it.

---

## 3. SPI frame format

16-bit frame, MSB first, SPI **mode 0** (CPOL=0, CPHA=0: master samples MOSI on
the rising edge, subordinate updates MISO on the falling edge). One frame per
`nCS` low pulse.

```
  bit:  15   14 13 12 11 10  9  8    7  6  5  4  3  2  1  0
       ┌────┬───────────────────┬───────────────────────────┐
       │ RW │   address[6:0]     │        data[7:0]           │
       └────┴───────────────────┴───────────────────────────┘
        └ command byte (bits 15:8) ┘ └── payload byte (7:0) ──┘
```

- **RW**: `1` = write, `0` = read.
- **address[6:0]**: register address (see §4).
- **data[7:0]**:
  - **write**: the byte to store, driven by the master on MOSI.
  - **read**: don't-care on MOSI; the subordinate returns the addressed
    register on **MISO** during these 8 bits (it has decoded the address by the
    end of the command byte).

This reuses the proven 16-bit frame from the onboarding `spi_peripheral.v`.

> **Read timing:** the command byte (bits 15:8) is fully received after the 8th
> SCLK rising edge. The subordinate then drives the addressed byte onto MISO,
> MSB first, on the following falling edges, so the master samples it on rising
> edges for bits 7:0 of the same frame.

> **Future extension (not in v1):** a burst/streaming read mode (8-bit address,
> then continuous bytes while `nCS` stays low) for high-throughput random
> readout to feed an NTT core. Documented now so the register map leaves room;
> v1 ships the simple one-byte-per-frame scheme.

---

## 4. Register map

| Addr  | Name        | R/W | Reset | Description |
|-------|-------------|-----|-------|-------------|
| `0x00`| `RNG_DATA`  | R   | —     | Next random byte. **Read-to-consume**: each completed read pulses `rng_pop` to advance the FIFO. Returns `0x00` if `rng_valid=0` (see `STATUS` bit 1). |
| `0x01`| `STATUS`    | R   | —     | Health-test status byte (`health_status`). See §5. |
| `0x02`| `ALARM`     | R   | —     | `{6'b0, fifo_empty, alarm}`. bit0 = `alarm`, bit1 = FIFO empty (no fresh randomness). |
| `0x03`| `ID`        | R   | `0x5A`| Constant device ID. Read it during bring-up to confirm the SPI link is alive. |
| `0x10`| `CTRL`      | W   | `0x00`| bit0 `enable`, bit1 `mode` (0=SHA-3,1=SHAKE), bit2 `reseed` (self-clearing pulse), bit3 `soft_rst` (self-clearing pulse). |

Reads of unmapped addresses return `0x00`. Writes to unmapped/read-only
addresses are ignored.

---

## 5. STATUS byte layout (proposal — confirm with @rahulearn2019)

Rahul's idea: one bit per statistical test, LSB = entropy. Starting layout:

| Bit | Meaning | Source test |
|-----|---------|-------------|
| 0   | Entropy OK | Repetition Count test (SP 800-90B) |
| 1   | Adaptive Proportion OK | Adaptive Proportion test (SP 800-90B) |
| 2   | Canary OK | Canary number monitor |
| 3   | Temperature OK | Temperature sensor |
| 7:4 | reserved | — |

`alarm` (the pin and `ALARM` reg bit0) = OR-reduction of the failing tests, i.e.
`alarm = ~(&health_status_used_bits)` — confirm exact polarity with Rahul.

---

## 6. The one design decision baked in here

**Random data is read-to-consume.** A plain "latest value" register would hand
out duplicate randomness on repeated reads — fatal for a TRNG. So `RNG_DATA`
reads from a FIFO and the SPI block pulses `rng_pop` at the end of each valid
read frame to advance it. Keccak owns the FIFO; SPI just pops. If the FIFO is
empty (`rng_valid=0`), the read returns `0x00`, does **not** pop, and sets the
FIFO-empty bit so the master can poll and retry.

---

## 7. Open questions for sign-off

- **@infinitymdm (keccak):** Is a byte-wide FIFO with `valid`/`pop` the right
  data handoff, or do you expose a wider word? Final `CTRL` bit definitions?
- **@rahulearn2019 (health):** Is the §5 STATUS bit layout right? Alarm polarity?
- **Team:** v1 one-byte-per-frame read OK, or do we need burst mode now for
  throughput?

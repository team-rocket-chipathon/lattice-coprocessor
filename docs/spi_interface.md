# SPI Subordinate Interface

Issue: #11 Design register-mapped SPI controller
Owner: Sarkar

The SPI subordinate is the chip's external interface. An off-chip host reads the
TRNG's random output (the SHAKE result) and the health-monitor status over a
4-wire SPI bus. This document defines the interface contract and the register map.

## 1. Where it sits

The SPI block reads two on-chip sources and exposes four external pins:

```
  keccak core     ->  result / valid / mode   ->  SPI  ->  SCLK / MOSI / MISO / nCS  (host)
  health monitor  ->  health_status / alarm   ->  SPI
```

The SPI drives 'ready' back to the keccak core (the read handshake). It does not
control the keccak core; enable, mode and reset are owned by the health monitor.

## 2. Ports

System:
```
  clk    in    system clock (SPI lines are oversampled in this domain)
  rst_n  in    active-low reset
```

SPI bus (spi_if.subordinate, SPI mode 0):
```
  sclk   in    SPI clock from the host (sampled, not a clock domain)
  cs_n   in    chip select, active-low
  mosi   in    host-out subordinate-in
  miso   out   host-in subordinate-out
```

Keccak read (keccak_if.consumer):
```
  result  in    RESULT_W-bit keccak output (default 512)
  valid   in    a result is available
  mode    in    FIPS202 mode; the SPI reads out only SHAKE-mode results
  ready   out   the SPI can accept a result; transfer occurs on valid and ready
```

Health status:
```
  health_status  in    HEALTH_W-bit status byte
  alarm          in    1 = entropy irregularity
```

## 3. SPI frame format

16-bit frame, MSB first, SPI mode 0:
```
  bit 15    : RW  (1 = write, 0 = read)
  bit 14..8 : address (7 bits)
  bit 7..0  : data (write) or byte returned on MISO (read)
```

For a read, the addressed byte is returned on MISO in the low 8 bits of the same
frame.

## 4. Register map

```
  0x00  RNG_DATA  R   Next byte of the current SHAKE result. Successive reads walk
                      through the 512-bit result, byte 0 (LSB) first. Returns 0x00
                      if no result is buffered (see ALARM bit 1).
  0x01  STATUS    R   Health-monitor status byte.
  0x02  ALARM     R   bit0 = alarm, bit1 = data_not_ready (no fresh result buffered).
  0x03  ID        R   Constant device ID (0x5A). Read during bring-up.
```

There are no writable registers: the SPI does not control the keccak core.

## 5. Keccak read path

The keccak result and the SPI bus run at very different rates, so the SPI takes a
one-shot copy:

1. When the keccak core asserts 'valid' for a SHAKE result and the SPI is ready,
   the SPI captures the full RESULT_W-bit result into a snapshot register.
2. The host reads the snapshot out byte-by-byte over SPI (RNG_DATA).
3. Reading the last byte releases the snapshot and re-asserts 'ready', so the core
   can produce the next result.

The SPI captures SHAKE-mode results only. Results produced in SHA-3 mode are the
conditioned seed and must not leave the chip, so they are never captured.

## 6. Parameters

```
  RESULT_W   keccak result width, must match keccak_if MAX_D (default 512)
  HEALTH_W   health-status width (default 8)
  DEVICE_ID  constant returned by the ID register (default 0x5A)
```

## 7. Open items

- Health-side hookup (health_status, alarm) is a placeholder until the
  health-monitor interface is defined.
- Readout contract: the host reads the full 512-bit block; reading the last byte
  re-arms 'ready'. Partial reads or an explicit release command are possible
  extensions.
- Simulation uses Verilator (the SystemVerilog interface ports are not supported
  by Icarus).

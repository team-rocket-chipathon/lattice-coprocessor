# SPDX-License-Identifier: MIT
# cocotb tests for spi_subordinate integrated with keccak_if.
# Drives 16-bit SPI mode-0 frames and mocks the keccak core from Python.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# Register map
ADDR_RNG_DATA = 0x00
ADDR_STATUS   = 0x01
ADDR_ALARM    = 0x02
ADDR_ID       = 0x03
DEVICE_ID     = 0x5A

# fips202::mode_t enum values
SHAKE128 = 0
SHAKE256 = 1
SHA3_512 = 5

RESULT_BYTES = 64            # 512-bit result
CLK_PER_HALF = 12            # system-clk cycles per SCLK half-period


async def reset(dut):
    dut.sclk.value = 0
    dut.mosi.value = 0
    dut.ncs.value = 1
    dut.kc_result.value = 0
    dut.kc_valid.value = 0
    dut.kc_mode.value = SHA3_512
    dut.health_status.value = 0
    dut.alarm.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 3)


async def spi_read(dut, addr):
    """Drive one 16-bit read frame; return the byte sampled on MISO."""
    cmd = (addr & 0x7F)            # RW=0
    dut.ncs.value = 0
    await ClockCycles(dut.clk, CLK_PER_HALF)
    for i in range(8):            # command byte
        dut.mosi.value = (cmd >> (7 - i)) & 1
        dut.sclk.value = 0
        await ClockCycles(dut.clk, CLK_PER_HALF)
        dut.sclk.value = 1
        await ClockCycles(dut.clk, CLK_PER_HALF)
    rdata = 0
    for i in range(8):            # data byte, sample MISO
        dut.sclk.value = 0
        await ClockCycles(dut.clk, CLK_PER_HALF)
        dut.sclk.value = 1
        await ClockCycles(dut.clk, CLK_PER_HALF)
        rdata = (rdata << 1) | int(dut.miso.value)
    dut.sclk.value = 0
    dut.ncs.value = 1
    await ClockCycles(dut.clk, CLK_PER_HALF)
    return rdata & 0xFF


async def present_shake_result(dut, value):
    """Mock keccak: present a SHAKE result and hold `valid` until the DUT snapshots it."""
    dut.kc_mode.value = SHAKE256
    dut.kc_result.value = value
    dut.kc_valid.value = 1
    for _ in range(50):
        await ClockCycles(dut.clk, 1)
        if int(dut.kc_ready.value) == 0:   # ready drops once the DUT captures
            break
    dut.kc_valid.value = 0


async def present_sha3_result(dut, value):
    """Mock keccak: present a SHA-3 result (the seed). The DUT must NOT capture it."""
    dut.kc_mode.value = SHA3_512
    dut.kc_result.value = value
    dut.kc_valid.value = 1
    await ClockCycles(dut.clk, 10)
    dut.kc_valid.value = 0


@cocotb.test()
async def test_read_shake_result(dut):
    """Snapshot a SHAKE result and stream all 64 bytes out over SPI."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    # known 512-bit value: byte i = (i*7 + 3) & 0xFF, little-endian
    value = 0
    for i in range(RESULT_BYTES):
        value |= ((i * 7 + 3) & 0xFF) << (8 * i)

    await present_shake_result(dut, value)

    # data should be available now
    a = await spi_read(dut, ADDR_ALARM)
    assert (a >> 1) & 1 == 0, "data should be ready after a SHAKE result"

    # read all 64 bytes, byte 0 first
    for i in range(RESULT_BYTES):
        b = await spi_read(dut, ADDR_RNG_DATA)
        assert b == ((i * 7 + 3) & 0xFF), f"byte {i}: got 0x{b:02X}"

    # after the last byte the snapshot is released
    a = await spi_read(dut, ADDR_ALARM)
    assert (a >> 1) & 1 == 1, "data_not_ready should be set after draining"
    dut._log.info("SHAKE readout OK")


@cocotb.test()
async def test_sha3_seed_not_captured(dut):
    """A SHA-3 result (conditioned seed) must never be exposed over SPI."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    await present_sha3_result(dut, 0xDEADBEEFCAFEBABE)

    a = await spi_read(dut, ADDR_ALARM)
    assert (a >> 1) & 1 == 1, "nothing should be buffered from a SHA-3 result"
    b = await spi_read(dut, ADDR_RNG_DATA)
    assert b == 0, "RNG_DATA must be 0 when nothing captured (seed not exposed)"
    dut._log.info("SHA-3 seed correctly ignored")


@cocotb.test()
async def test_status_alarm_id(dut):
    """ID, STATUS and ALARM register reads."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    assert await spi_read(dut, ADDR_ID) == DEVICE_ID

    dut.health_status.value = 0xA5
    await ClockCycles(dut.clk, 2)
    assert await spi_read(dut, ADDR_STATUS) == 0xA5

    dut.alarm.value = 1
    await ClockCycles(dut.clk, 2)
    # bit0 = alarm (1), bit1 = data_not_ready (1, nothing buffered)
    assert await spi_read(dut, ADDR_ALARM) == 0x03
    dut._log.info("status/alarm/id OK")

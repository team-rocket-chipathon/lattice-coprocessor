# SPDX-License-Identifier: MIT
# cocotb tests for rct_monitor (NIST SP 800-90B Repetition Count Test).
# WIDTH/CUTOFF must match tb.sv.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

CUTOFF = 8
WIDTH = 8


async def reset(dut):
    dut.sample.value = 0
    dut.sample_valid.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def feed(dut, value):
    """Drive exactly one valid sample."""
    dut.sample.value = value
    dut.sample_valid.value = 1
    await ClockCycles(dut.clk, 1)
    dut.sample_valid.value = 0


@cocotb.test()
async def test_stuck_source_alarms(dut):
    """CUTOFF identical samples in a row → alarm, and not one repeat sooner."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    assert int(dut.alarm.value) == 0

    for i in range(1, CUTOFF + 1):
        await feed(dut, 0xAA)
        await ClockCycles(dut.clk, 1)  # let the registered alarm settle
        if i < CUTOFF:
            assert int(dut.alarm.value) == 0, f"alarm too early at repeat {i}"
        else:
            assert int(dut.alarm.value) == 1, f"alarm should fire at repeat {CUTOFF}"

    dut._log.info("stuck-source detection OK")


@cocotb.test()
async def test_varying_source_ok(dut):
    """A changing stream must never alarm."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    seq = [0x00, 0xFF, 0x00, 0xFF, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC] * 3
    for v in seq:
        await feed(dut, v)
    await ClockCycles(dut.clk, 2)
    assert int(dut.alarm.value) == 0, "varying stream should not alarm"

    dut._log.info("varying-source OK")


@cocotb.test()
async def test_run_just_below_cutoff_ok(dut):
    """CUTOFF-1 repeats, then a different sample: no alarm."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    for _ in range(CUTOFF - 1):
        await feed(dut, 0x55)
    await ClockCycles(dut.clk, 1)
    assert int(dut.alarm.value) == 0, "no alarm before CUTOFF repeats"

    await feed(dut, 0x66)  # streak broken
    await feed(dut, 0x66)
    await ClockCycles(dut.clk, 1)
    assert int(dut.alarm.value) == 0, "broken streak should not alarm"

    dut._log.info("below-cutoff OK")

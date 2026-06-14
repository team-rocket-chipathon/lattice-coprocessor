# SPDX-License-Identifier: MIT
# cocotb tests for spi_subordinate. Drives 16-bit SPI mode-0 frames and models
# the keccak FIFO + health monitor in Python. See ../../../docs/spi_interface.md.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

# Register map (docs/spi_interface.md §4)
ADDR_RNG_DATA = 0x00
ADDR_STATUS   = 0x01
ADDR_ALARM    = 0x02
ADDR_ID       = 0x03
ADDR_CTRL     = 0x10
DEVICE_ID     = 0x5A

# System-clk cycles per SCLK half-period. The DUT oversamples SCLK in the clk
# domain, so this must be comfortably larger than the synchroniser depth.
CLK_PER_HALF = 20


async def reset_dut(dut):
    dut.sclk.value = 0
    dut.mosi.value = 0
    dut.ncs.value = 1
    dut.rng_data.value = 0
    dut.rng_valid.value = 0
    dut.health_status.value = 0
    dut.alarm.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


async def spi_frame(dut, rw, addr, wdata=0):
    """Drive one 16-bit SPI mode-0 frame; return the byte sampled on MISO.

    Frame: [15]=RW [14:8]=addr [7:0]=data, MSB first. Master samples MISO on the
    rising edge (here: at the end of each data-bit high phase).
    """
    cmd = ((rw & 1) << 7) | (addr & 0x7F)
    dut.ncs.value = 0
    await ClockCycles(dut.clk, CLK_PER_HALF)

    # command byte
    for i in range(8):
        dut.mosi.value = (cmd >> (7 - i)) & 1
        dut.sclk.value = 0
        await ClockCycles(dut.clk, CLK_PER_HALF)
        dut.sclk.value = 1
        await ClockCycles(dut.clk, CLK_PER_HALF)

    # data byte (MOSI = wdata for writes; for reads we sample MISO)
    rdata = 0
    for i in range(8):
        dut.mosi.value = (wdata >> (7 - i)) & 1
        dut.sclk.value = 0
        await ClockCycles(dut.clk, CLK_PER_HALF)
        dut.sclk.value = 1
        await ClockCycles(dut.clk, CLK_PER_HALF)
        rdata = (rdata << 1) | int(dut.miso.value)

    dut.sclk.value = 0
    dut.ncs.value = 1
    await ClockCycles(dut.clk, CLK_PER_HALF)
    return rdata & 0xFF


async def catch_pulse(sig):
    """Resolve once `sig` goes high (for sampling 1-cycle control pulses)."""
    await RisingEdge(sig)
    return True


async def spi_write(dut, addr, data):
    await spi_frame(dut, 1, addr, data)


async def spi_read(dut, addr):
    return await spi_frame(dut, 0, addr, 0)


async def keccak_fifo(dut, values):
    """Model the keccak output FIFO: present the head on rng_data, advance on
    each rng_pop pulse, drop rng_valid when drained."""
    idx = 0
    dut.rng_data.value = values[0]
    dut.rng_valid.value = 1
    while True:
        await RisingEdge(dut.rng_pop)
        idx += 1
        if idx < len(values):
            dut.rng_data.value = values[idx]
            dut.rng_valid.value = 1
        else:
            dut.rng_data.value = 0
            dut.rng_valid.value = 0


@cocotb.test()
async def test_reads_and_status(dut):
    """ID, STATUS and ALARM register reads."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    val = await spi_read(dut, ADDR_ID)
    assert val == DEVICE_ID, f"ID: got 0x{val:02X}, expected 0x{DEVICE_ID:02X}"

    dut.health_status.value = 0xA5
    await ClockCycles(dut.clk, 2)
    val = await spi_read(dut, ADDR_STATUS)
    assert val == 0xA5, f"STATUS: got 0x{val:02X}, expected 0xA5"

    # ALARM = {6'b0, ~rng_valid, alarm}
    dut.rng_valid.value = 1
    dut.alarm.value = 0
    await ClockCycles(dut.clk, 2)
    val = await spi_read(dut, ADDR_ALARM)
    assert val == 0x00, f"ALARM(valid,ok): got 0x{val:02X}, expected 0x00"

    dut.alarm.value = 1
    await ClockCycles(dut.clk, 2)
    val = await spi_read(dut, ADDR_ALARM)
    assert val == 0x01, f"ALARM(valid,alarm): got 0x{val:02X}, expected 0x01"

    dut.rng_valid.value = 0
    await ClockCycles(dut.clk, 2)
    val = await spi_read(dut, ADDR_ALARM)
    assert val == 0x03, f"ALARM(empty,alarm): got 0x{val:02X}, expected 0x03"

    dut._log.info("reads/status OK")


@cocotb.test()
async def test_rng_read_to_consume(dut):
    """Each RNG_DATA read returns a fresh byte and pops the FIFO."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    stream = [0x11, 0x22, 0x33, 0x44]
    cocotb.start_soon(keccak_fifo(dut, stream))
    await ClockCycles(dut.clk, 2)

    for expected in stream:
        val = await spi_read(dut, ADDR_RNG_DATA)
        assert val == expected, f"RNG_DATA: got 0x{val:02X}, expected 0x{expected:02X}"

    # FIFO drained -> reads return 0x00 (and do not pop)
    val = await spi_read(dut, ADDR_RNG_DATA)
    assert val == 0x00, f"RNG_DATA(empty): got 0x{val:02X}, expected 0x00"

    dut._log.info("read-to-consume OK")


@cocotb.test()
async def test_ctrl_writes(dut):
    """CTRL register: level bits (enable/mode) and self-clearing pulses."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # enable=1, mode=1
    await spi_write(dut, ADDR_CTRL, 0x03)
    await ClockCycles(dut.clk, 3)
    assert int(dut.ctrl_enable.value) == 1, "ctrl_enable should be 1"
    assert int(dut.ctrl_mode.value) == 1, "ctrl_mode should be 1"

    # clear
    await spi_write(dut, ADDR_CTRL, 0x00)
    await ClockCycles(dut.clk, 3)
    assert int(dut.ctrl_enable.value) == 0, "ctrl_enable should clear"
    assert int(dut.ctrl_mode.value) == 0, "ctrl_mode should clear"

    # reseed pulse (bit2), enable also set
    watch = cocotb.start_soon(catch_pulse(dut.ctrl_reseed))
    await spi_write(dut, ADDR_CTRL, 0x05)
    await ClockCycles(dut.clk, 5)
    assert watch.done(), "ctrl_reseed should pulse on write of bit2"
    assert int(dut.ctrl_enable.value) == 1, "ctrl_enable should be 1"

    # soft reset pulse (bit3)
    watch = cocotb.start_soon(catch_pulse(dut.ctrl_soft_rst))
    await spi_write(dut, ADDR_CTRL, 0x08)
    await ClockCycles(dut.clk, 5)
    assert watch.done(), "ctrl_soft_rst should pulse on write of bit3"

    dut._log.info("control writes OK")

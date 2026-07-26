# SPDX-FileCopyrightText: 2026 Taiwo Opesade
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer


def pack_inputs(data_in, mode=0, clr=0):
    """Build the ui_in byte: bit5=CLR, bit4=MODE, bits[3:0]=DATA_IN."""
    return (clr << 5) | (mode << 4) | (data_in & 0xF)


async def step(dut):
    """Advance one full clock cycle, then settle off the edge boundary.

    Chaining bare `await ClockCycles(dut.clk, 1)` calls back-to-back (with
    no simulation time passing between them) was observed to coalesce onto
    the same edge instead of advancing a fresh cycle each time - and in
    gate-level (UNIT_DELAY=#1) simulation, real per-gate propagation delays
    mean a 1ns settle isn't quite enough margin either. 100ns is still under
    1% of the 10us clock period, so it stays a "same cycle" read while
    giving every synthesized gate plenty of room to settle.
    """
    await ClockCycles(dut.clk, 1)
    await Timer(100, unit="ns")


def read_uo(dut):
    return int(dut.uo_out.value)


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    for _ in range(10):
        await step(dut)
    dut.rst_n.value = 1
    await step(dut)

    uo = read_uo(dut)
    assert uo & 0xF == 0
    assert (uo >> 5) & 1 == 1  # zero flag set after reset

    # Add 5 to the (zeroed) accumulator -> 5
    dut.ui_in.value = pack_inputs(5, mode=0, clr=0)
    await step(dut)
    uo = read_uo(dut)
    assert uo & 0xF == 5
    assert (uo >> 5) & 1 == 0

    # Add 3 -> 8
    dut.ui_in.value = pack_inputs(3, mode=0, clr=0)
    await step(dut)
    uo = read_uo(dut)
    assert uo & 0xF == 8

    # Add 10 -> 18 wraps to 2, with carry out set
    dut.ui_in.value = pack_inputs(10, mode=0, clr=0)
    await step(dut)
    uo = read_uo(dut)
    assert uo & 0xF == 2
    assert (uo >> 4) & 1 == 1

    # Add 0 -> carry flag clears again since this add didn't overflow
    dut.ui_in.value = pack_inputs(0, mode=0, clr=0)
    await step(dut)
    uo = read_uo(dut)
    assert uo & 0xF == 2
    assert (uo >> 4) & 1 == 0

    # Load mode overwrites the accumulator directly, ignoring the adder
    dut.ui_in.value = pack_inputs(9, mode=1, clr=0)
    await step(dut)
    uo = read_uo(dut)
    assert uo & 0xF == 9

    # Clear overrides everything, including load
    dut.ui_in.value = pack_inputs(9, mode=1, clr=1)
    await step(dut)
    uo = read_uo(dut)
    assert uo & 0xF == 0
    assert (uo >> 5) & 1 == 1

    # Load 7, then assert async reset mid-operation and check it clears
    # immediately, without waiting for a clock edge.
    dut.ui_in.value = pack_inputs(7, mode=1, clr=0)
    await step(dut)
    uo = read_uo(dut)
    assert uo & 0xF == 7

    dut.rst_n.value = 0
    await Timer(100, unit="ns")  # still << one clock period, well before the next edge
    uo = read_uo(dut)
    assert uo & 0xF == 0
    assert (uo >> 5) & 1 == 1
    dut.rst_n.value = 1

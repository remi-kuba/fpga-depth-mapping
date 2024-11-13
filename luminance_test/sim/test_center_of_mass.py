import cocotb
import os
import random
import sys
from math import log
import logging
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly,with_timeout
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner



    
@cocotb.test()
async def test_increasing(dut):
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    # cocotb.start_soon(test_center_of_mass(dut))
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 3) # wait three clock cycles
    dut.rst_in.value = 0
    dut.x_in.value = 0
    dut.y_in.value = 0
    dut.valid_in.value = 0
    dut.tabulate_in.value = 0
    await FallingEdge(dut.clk_in)
    await ClockCycles(dut.clk_in, 3)

    dut.tabulate_in.value = 1 # should not give anything
    await ClockCycles(dut.clk_in, 1)
    dut.tabulate_in.value = 0
    dut.valid_in.value = 1
    for i in range(700):
        dut.x_in.value = i
        dut.y_in.value = i
        if i == 699:
            dut.tabulate_in.value = 1
        await ClockCycles(dut.clk_in, 1, rising=False)
        await FallingEdge(dut.clk_in)
    dut.tabulate_in.value = 0
    await RisingEdge(dut.valid_out)
    assert dut.x_out.value == 348 or dut.x_out.value == 349, f"x_out: {dut.x_out.value}"
    assert dut.y_out.value == 348 or dut.y_out.value == 349, f"y_out: {dut.y_out.value}"
    await ClockCycles(dut.clk_in, 20)

@cocotb.test()
async def test_one_increasing(dut):
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    # cocotb.start_soon(test_center_of_mass(dut))
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 3) # wait three clock cycles
    dut.rst_in.value = 0
    dut.x_in.value = 0
    dut.y_in.value = 0
    dut.valid_in.value = 0
    dut.tabulate_in.value = 0
    await FallingEdge(dut.clk_in)
    await ClockCycles(dut.clk_in, 3)
    dut.valid_in.value = 1
    for i in range(700):
        dut.x_in.value = i
        dut.y_in.value = 10
        if i == 699:
            dut.tabulate_in.value = 1
        await ClockCycles(dut.clk_in, 1, rising=False)
        await FallingEdge(dut.clk_in)
    dut.tabulate_in.value = 0
    dut.valid_in.value = 0
    await RisingEdge(dut.valid_out)
    assert dut.x_out.value == 348 or dut.x_out.value == 349, f"x_out: {dut.x_out.value}"
    assert dut.y_out.value == 10, f"y_out: {dut.y_out.value}"
    await ClockCycles(dut.clk_in, 30)


@cocotb.test()
async def test_one_bit(dut):
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    # cocotb.start_soon(test_center_of_mass(dut))
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 3) # wait three clock cycles
    dut.rst_in.value = 0
    dut.x_in.value = 0
    dut.y_in.value = 0
    dut.valid_in.value = 0
    dut.tabulate_in.value = 0
    await ClockCycles(dut.clk_in, 3)
    await FallingEdge(dut.clk_in)

    dut.valid_in.value = 1
    dut.x_in.value = 123
    dut.y_in.value = 456
    # dut.tabulate_in.value = 1

    await ClockCycles(dut.clk_in, 1)
    await FallingEdge(dut.clk_in)
    dut.valid_in.value = 0
    dut.tabulate_in.value = 1
    await ClockCycles(dut.clk_in, 1)
    await FallingEdge(dut.clk_in)
    dut.tabulate_in.value = 0
    
    dut._log.info("Waiting for rising edge...")
    await RisingEdge(dut.valid_out)
    assert dut.x_out.value == 123, f"x_out: {dut.x_out.value}"
    assert dut.y_out.value == 456, f"y_out: {dut.y_out.value}"

    await ClockCycles(dut.clk_in, 20)

@cocotb.test()
async def test_whole_frame(dut):
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    # cocotb.start_soon(test_center_of_mass(dut))
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 3) # wait three clock cycles
    dut.rst_in.value = 0
    dut.x_in.value = 0
    dut.y_in.value = 0
    dut.valid_in.value = 0
    dut.tabulate_in.value = 0
    await FallingEdge(dut.clk_in)
    await ClockCycles(dut.clk_in, 3)
    dut.valid_in.value = 1
    for j in range(768):
        for i in range(1024):
            dut.x_in.value = i
            dut.y_in.value = j
            if j == 767 and i == 1023:
                dut.tabulate_in.value = 1
            await ClockCycles(dut.clk_in, 1, rising=False)
            # await FallingEdge(dut.clk_in)
    dut.tabulate_in.value = 0
    dut.valid_in.value = 0

    dut._log.info("Waiting for rising edge...")
    await RisingEdge(dut.valid_out)
    await ReadOnly()
    assert dut.x_out.value == 510 or dut.x_out.value == 511, f"x_out: {dut.x_out.value}"
    assert dut.y_out.value == 382 or dut.y_out.value == 383, f"y_out: {dut.y_out.value}"
    await ClockCycles(dut.clk_in, 30)


def com():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "center_of_mass.sv", proj_path / "hdl" / "divider.sv"]
    build_test_args = ["-Wall"]
    parameters = {} 
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="center_of_mass",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="center_of_mass",
        test_module="test_center_of_mass",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    com()
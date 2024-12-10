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
import random

@cocotb.test()
async def test_addr_counter(dut):
    """cocotb test for address counter"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 3, rising = False)

    dut.rst_in.value = 0
    dut.evt_in.value = 0
    for i in range(40):
        if i == 39:
            dut.rst_in.value = 1
            await ClockCycles(dut.clk_in, 1)
            dut.rst_in.value = 0
        dut.evt_in.value = not dut.evt_in.value
        await ClockCycles(dut.clk_in, random.randint(1,13))





def addr_counter_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "addr_counter.sv", proj_path / "hdl" / "spec_evt_counter.sv"]
    build_test_args = ["-Wall"]
    parameters = {'HCOUNT': 10, 'VCOUNT': 5} #!!!change these to do different versions
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="addr_counter",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="addr_counter",
        test_module="test_addr_counter",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    addr_counter_runner()
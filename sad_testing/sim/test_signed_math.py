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
from PIL import Image
import numpy as np


left_kernel = [(43,87,161), (64,215,202), (229,109,241)]
right_kernel = [(22,42,151), (90,220,200), (223,131,241)]

def line_out(top, middle, bottom):
    return bottom << 16 | middle << 8 | top

@cocotb.test()
async def test_signed_math(dut):
    """cocotb test for signed_math calculation"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 3, rising = False)
    dut.rst_in.value = 0
    # dut.a_in.value = 2
    # dut.b_in.value = 31

    for i in range(3):
        left = left_kernel[i]
        right = right_kernel[i]
        dut.left_in.value = line_out(*left)
        dut.right_in.value = line_out(*right)
        dut.data_valid_in.value = 1
        await ClockCycles(dut.clk_in, 1)

    dut.data_valid_in.value = 0


    await ClockCycles(dut.clk_in, 10)

        


def signed_math_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "signed_math.sv"]
    build_test_args = ["-Wall"]
    parameters = {} 
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="signed_math",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="signed_math",
        test_module="test_signed_math",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    signed_math_runner()
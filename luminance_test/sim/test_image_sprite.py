import cocotb
import os
import sys
from math import log
import logging
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly,with_timeout
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner


@cocotb.test()
async def test_a(dut):
    """cocotb test for image_sprite"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.pixel_clk_in, 10, units="ns").start())
    dut.rst_in.value = 0
    await ClockCycles(dut.pixel_clk_in,1)
    dut.rst_in.value = 1
    await ClockCycles(dut.pixel_clk_in,5)
    dut.x_in.value = 256
    dut.y_in.value = 256
    dut.vcount_in.value = 380
    dut.rst_in.value = 0
    await ClockCycles(dut.pixel_clk_in,10)
    for x in range(1026):
      await FallingEdge(dut.pixel_clk_in)
      dut.hcount_in.value = x
      await RisingEdge(dut.pixel_clk_in)

def is_runner():
    """Image Sprite Tester."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "image_sprite.sv"]
    sources += [proj_path / "hdl" / "xilinx_single_port_ram_read_first.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="image_sprite",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="image_sprite",
        test_module="test_image_sprite",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    is_runner()

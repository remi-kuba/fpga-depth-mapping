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


color_bar = [0xAB, 0xCD, 
             0xFF, 0xE0, 
             0x07, 0xFF, 
             0x07, 0xE0, 
             0xF8, 0x1F, 
             0xF8, 0x00, 
             0x00, 0x1F, 
             0xAB, 0xAB, 0xAA]

async def test_pixel_reconstruct(dut):
    count = 0
    vs_count = 0
    while True:
        await ClockCycles(dut.clk_in, 2, rising=False)
        # await FallingEdge(dut.clk_in) /
        dut.camera_pclk_in = 1
        await ClockCycles(dut.clk_in, 1, rising=False)
        if vs_count == 4:
            dut.camera_vs_in = 0
            dut.camera_hs_in = 1
            for _ in range(21):
                await FallingEdge(dut.clk_in)
                dut.camera_pclk_in = 1
                await ClockCycles(dut.clk_in, 2)
                await FallingEdge(dut.clk_in)
                dut.camera_pclk_in = 0
                await ClockCycles(dut.clk_in, 2)
            vs_count = 0
            dut.camera_vs_in = 1
        else:
            dut.camera_hs_in = 1

        if count < 17:
            dut.camera_hs_in = 1 
            dut.camera_data_in.value = color_bar[count]
        elif vs_count != 4:
            dut.camera_hs_in = 0
            dut.camera_data_in.value = 0xAA
        await ClockCycles(dut.clk_in, 1, rising=False)
        await RisingEdge(dut.clk_in)
        dut.camera_pclk_in = 0

        if count < 21:
            count += 1
        else:
            count = 0
            vs_count += 1

@cocotb.test()
async def test_a(dut):
    """cocotb test for video signal generator"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    # cocotb.start_soon(Clock(dut.camera_pclk_in, 20, units="ns").start())
    cocotb.start_soon(test_pixel_reconstruct(dut))
    # cocotb.start_soon(test_video(dut))
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    dut.camera_data_in.value = 0xAA
    dut.camera_hs_in = 1
    dut.camera_vs_in = 1
    await ClockCycles(dut.clk_in, 3) #wait three clock cycles
    await  FallingEdge(dut.clk_in)
    dut.rst_in.value = 0 #unreset device

    await ClockCycles(dut.clk_in, 10)
    await ClockCycles(dut.clk_in, 3000)

def video_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "pixel_reconstruct.sv"]
    build_test_args = ["-Wall"]
    parameters = {'HCOUNT_WIDTH': 5, 
                  'VCOUNT_WIDTH': 3} 
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="pixel_reconstruct",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="pixel_reconstruct",
        test_module="test_pixel_reconstruct",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    video_runner()
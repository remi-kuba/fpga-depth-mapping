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

def stereo_match(left_file, right_file, kernel, max_offset):
    left_img = Image.open(left_file).convert('L')
    left = np.asarray(left_img)
    right_img = Image.open(right_file).convert('L')
    right = np.asarray(right_img) 
    w, h = left_img.size
    depth = np.zeros((w, h), np.uint8)
    depth.shape = h, w

    kernel_half = int(kernel / 2)
    offset_adjust = 255 / max_offset  # this is used to map depth map output to 0-255 range
      
    for y in range(kernel_half, h - kernel_half):              
        for x in range(kernel_half, w - kernel_half):
            best_offset = 0
            prev_sad = 65534
            
            for offset in range(max_offset+1):               
                sad = 0
                sad_temp = 0
                for v in range(-kernel_half, kernel_half):
                    for u in range(-kernel_half, kernel_half):
                        sad_temp = abs(int(left[y+v, x+u]) - int(right[y+v, (x+u) - offset]) )
                        # sad_temp = int(left[y+v, x+u]) - int(right[y+v, (x+u) - offset])
                        sad += sad_temp
                if sad < prev_sad:
                    prev_sad = sad
                    best_offset = offset
            depth[y, x] = best_offset * offset_adjust
    return w, h, left_img, right_img, depth


def line_out(img, x, y):
    return img.getpixel((x,y+1)) << 16 | img.getpixel((x,y)) << 8 | img.getpixel((x,y-1))


async def test_data_out(dut):
    w, h, left_img, right_img, depth = stereo_match("../../data/Tsukuba_L.png", "../../data/Tsukuba_R.png", 3, 10)
    result_img = Image.new('L', (w,h))
    while True:
        await RisingEdge(dut.data_valid_out)
        hc_out = int(dut.hcount_out.value)
        vc_out = int(dut.vcount_out.value)
        pixel = int(dut.line_out.value)
        dut._log.info(f"Pixel: {(vc_out, hc_out)} with grey: {pixel}, wanted: {depth[vc_out][hc_out]}")
        result_img.putpixel((hc_out, vc_out), pixel)
        result_img.save("../../output/output.png", "PNG")
        
        await ClockCycles(dut.clk_in, 1, rising=False)
        dut.data_valid_in.value = 0
        await ClockCycles(dut.clk_in, 12, rising=False)

@cocotb.test()
async def test_sad(dut):
    """cocotb test for sad calculation"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    cocotb.start_soon(test_data_out(dut))
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 3, rising = False)

    w, h, left_img, right_img, depth = stereo_match("../../data/Tsukuba_L.png", "../../data/Tsukuba_R.png", 3, 10)

    dut.rst_in.value = 0
    await ClockCycles(dut.clk_in, 3, rising = False)
    # for y in range(1, h-1):
    #     for x in range(w):
    for y in range(1, 3):
        for x in range(w):
            left_line = line_out(left_img, x, y)
            right_line = line_out(right_img, x, y)
            dut.hcount_in.value = x
            dut.vcount_in.value = y
            dut.left_data_in.value = left_line
            dut.right_data_in.value = right_line
            dut.data_valid_in.value = 1
            await ClockCycles(dut.clk_in, 1, rising=False)
            dut.data_valid_in.value = 0
            # await FallingEdge(dut.busy_out)
            await ClockCycles(dut.clk_in, 13, rising=False)
        
        


def sad_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "sad.sv"]
    build_test_args = ["-Wall"]
    parameters = {} 
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="sad",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="sad",
        test_module="test_sad",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    sad_runner()
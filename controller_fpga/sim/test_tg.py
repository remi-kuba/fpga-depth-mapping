import cocotb
import os
import random
import sys
import logging
from pathlib import Path
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly,with_timeout
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner
 
 
async def generate_clock(clock_wire):
	while True: # repeat forever
		clock_wire.value = 1
		await Timer(5,units="ns")
		clock_wire.value = 0
		await Timer(5,units="ns")

@cocotb.test()
async def first_test(dut):
    """First cocotb test?"""
    dut.rst_in = 1
    # dut.camera_vs_in = 1
    # dut.camera_hs_in = 1
    # dut.pixel_hcount_out = 0x298
    # dut.pixel_vcount_out = 0x271
    # dut.pixel_valid_out = 0
    # dut.pixel_data_out = 0xf01f
    # dut.half_pixel_ready = 0
    # dut.pclk_prev = 0
    # dut.last_sampled_data = 0xf0


    await cocotb.start( generate_clock( dut.clk_in ) ) #launches clock
    # dut.camera_data_in = 0x1f
    # await ClockCycles(dut.clk_in,1,rising=False)    
    # dut.rst_in = 0
    # dut.camera_data_in = 0x00
    # await ClockCycles(dut.clk_in,1,rising=False)    
    # dut.camera_pclk_in.value = 1
    # dut.pixel_hcount_out = 0x4f7
    # dut.pixel_vcount_out = 0x26f
    
    dut.write_axis_tlast.value = 0
    dut.read_axis_af.value = 0
    dut.app_wdf_wren=1
    dut.app_rd_data_valid = 1
    dut.app_rdy = 1
    dut.app_wdf_rdy = 1
    dut.write_axis_ready = 1
    dut.read_request_ready = 1
    dut.read_axis_ready = 1

    for i in range(115200): #feed in 115200, 128-bit inputs (all 0xdeadbee)
        dut.write_axis_data.value = 0xdeadbee
        dut.write_axis_valid.value = 1
        dut.app_rd_data_valid.value = 1
        dut.app_wdf_rdy.value = 1
        if (i == 115199):
            dut.write_axis_tlast.value = 1
        await ClockCycles(dut.clk_in,1,rising=False)   
    dut.write_axis_tlast.value = 0
    dut.write_axis_valid.value = 0
    dut.app_rd_data_valid.value = 0
    await ClockCycles(dut.clk_in,5,rising=False)   
    for i in range(115200): #feed in 115200, 128-bit inputs (all 0xdeadbee)
        dut.write_axis_data.value = 0xabeceda
        dut.write_axis_valid.value = 1
        dut.app_rd_data_valid.value = 1
        dut.app_wdf_rdy.value = 1
        if (i == 115199):
            dut.write_axis_tlast.value = 1
        await ClockCycles(dut.clk_in,1,rising=False)   
    dut.write_axis_tlast.value = 0
    dut.read_axis_ready.value = dut.write_axis_tlast.value

    await ClockCycles(dut.clk_in,100000,rising=False)   







"""the code below should largely remain unchanged in structure, though the specific files and things
specified should get updated for different simulations.
"""
def camera_runner():
    """Simulate the uart using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "traffic_generator.sv", proj_path / "hdl" / "evt_counter.sv"] #grow/modify this as needed.
    build_test_args = ["-Wall"]#,"COCOTB_RESOLVE_X=ZEROS"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="traffic_generator",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="traffic_generator",
        test_module="test_tg",
        test_args=run_test_args,
        waves=True
    )
 
if __name__ == "__main__":
    camera_runner()
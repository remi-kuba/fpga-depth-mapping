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
    # reset device
    dut.rst_in = 1

    await cocotb.start( generate_clock( dut.clk_in ) ) #launches clock
    # start device
    dut.rst_in = 0

    # set initial values
    # all write tlast values -> 0
    dut.wr_cam1_axis_tlast.value = 0
    dut.wr_cam2_axis_tlast.value = 0
    dut.wr_sad_axis_tlast.value = 0

    #all read af values -> 0
    dut.r_cam1_axis_af.value = 0
    dut.r_cam2_axis_af.value = 0
    dut.r_hdmi_axis_af.value = 0

    # All ready signals -> 1
    dut.wr_cam1_axis_ready = 1
    dut.wr_cam2_axis_ready = 1
    dut.wr_sad_axis_ready = 1

    dut.r_cam1_axis_ready = 1
    dut.r_cam2_axis_ready = 1
    dut.r_hdmi_axis_ready = 1

    dut.read_request_ready = 1

    # MIG vals (wren, rd_data_valid, rdy, wdf_rdy) -> 1
    dut.app_wdf_wren=1
    dut.app_rd_data_valid = 1
    dut.app_rdy = 1
    dut.app_wdf_rdy = 1

    # Random selection of inputs
    inputVals = [0xdeadbee, 0xfeedaaa, 0xaacceeb, 0xdeffeba, 0xadafeba]
    for i in range(3*14400): 
        #feed in 14400, 128-bit inputs for 3 different input FIFOs
        dut.wr_cam1_axis_data.value = random.choice(inputVals)
        dut.wr_cam2_axis_data.value = random.choice(inputVals)
        dut.wr_sad_axis_data.value = random.choice(inputVals)
        # all write and read valid
        dut.wr_cam1_axis_valid.value = 1
        dut.wr_cam2_axis_valid.value = 1
        dut.wr_sad_axis_valid.value = 1
        dut.app_rd_data_valid.value = 1
        dut.app_wdf_rdy.value = 1

        if (i == (3*14400)-1):
            dut.wr_cam1_axis_tlast.value = 1
            dut.wr_cam2_axis_tlast.value = 1
            dut.wr_sad_axis_tlast.value = 1
        # Every 3 UI clock cycles will read/write 1x128-bit buffer / FIFO
        await ClockCycles(dut.clk_in,3,rising=False)   
    dut.wr_cam1_axis_tlast.value = 0
    dut.wr_cam2_axis_tlast.value = 0
    dut.wr_sad_axis_tlast.value = 0
    dut.wr_cam1_axis_valid.value = 0
    dut.wr_cam2_axis_valid.value = 0
    dut.wr_sad_axis_valid.value = 0
    dut.app_rd_data_valid.value = 0
    await ClockCycles(dut.clk_in,10,rising=False)  

    # send another frame after break
    # for i in range(3*14400): 
    #     #feed in 14400, 128-bit inputs for 3 different input FIFOs
    #     dut.wr_cam1_axis_data.value = random.choice(inputVals)
    #     dut.wr_cam2_axis_data.value = random.choice(inputVals)
    #     dut.wr_sad_axis_data.value = random.choice(inputVals)
    #     # all write and read valid
    #     dut.wr_cam1_axis_valid.value = 1
    #     dut.wr_cam2_axis_valid.value = 1
    #     dut.wr_sad_axis_valid.value = 1
    #     dut.app_rd_data_valid.value = 1
    #     dut.app_wdf_rdy.value = 1

    #     if (i == (3*14400)-1):
    #         dut.wr_cam1_axis_tlast.value = 1
    #         dut.wr_cam2_axis_tlast.value = 1
    #         dut.wr_sad_axis_tlast.value = 1
    #     # Every 3 UI clock cycles will read/write 1x128-bit buffer / FIFO
    #     await ClockCycles(dut.clk_in,3,rising=False)   


    # for i in range(115200): #feed in 115200, 128-bit inputs (all 0xdeadbee)
    #     dut.write_axis_data.value = 0xabeceda
    #     dut.write_axis_valid.value = 1
    #     dut.app_rd_data_valid.value = 1
    #     dut.app_wdf_rdy.value = 1
    #     if (i == 115199):
    #         dut.write_axis_tlast.value = 1
    #     await ClockCycles(dut.clk_in,1,rising=False)   
    # dut.write_axis_tlast.value = 0
    # dut.read_axis_ready.value = dut.write_axis_tlast.value

    await ClockCycles(dut.clk_in,10000,rising=False)   







"""the code below should largely remain unchanged in structure, though the specific files and things
specified should get updated for different simulations.
"""
def camera_runner():
    """Simulate the uart using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "traffic_generator.sv", proj_path / "hdl_done" / "evt_counter.sv"] #grow/modify this as needed.
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
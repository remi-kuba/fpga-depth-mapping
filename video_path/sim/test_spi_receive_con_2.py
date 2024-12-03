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
async def test_spi_receive_con_2(dut):
    """cocotb test for peripheral spi sender"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 3, rising = False)

    dut.rst_in.value = 0
    await ClockCycles(dut.clk_in, 3, rising = False)
    
    dut.chip_sel_in.value = 0
    dut.chip_clk_in.value = 0
    dut.chip_data_in.value = 0xA
    dut.final_pixel_in.value = 0
    await ClockCycles(dut.clk_in, 3, rising=False)
    dut.chip_clk_in.value = 1
    await ClockCycles(dut.clk_in, 3, rising=False)
    dut.chip_clk_in.value = 0
    dut.chip_data_in.value = 0x5
    await ClockCycles(dut.clk_in, 3, rising=False)
    dut.chip_clk_in.value = 1
    await ClockCycles(dut.clk_in, 3, rising=False)
    dut.chip_sel_in.value = 0
    dut.chip_clk_in.value = 0
    dut.chip_data_in.value = 0xB
    dut.final_pixel_in.value = 1
    await ClockCycles(dut.clk_in, 3, rising=False)
    dut.chip_clk_in.value = 1
    await ClockCycles(dut.clk_in, 3, rising=False)
    dut.chip_clk_in.value = 0
    dut.final_pixel_in.value = 0
    dut.chip_data_in.value = 0xE
    await ClockCycles(dut.clk_in, 3, rising=False)
    dut.chip_clk_in.value = 1
    await ClockCycles(dut.clk_in, 3, rising=False)
    dut.chip_sel_in.value = 1

    await ClockCycles(dut.clk_in, 20)




def spi_receive_con_2_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "spi_receive_con_2.sv"]
    build_test_args = ["-Wall"]
    parameters = {'DATA_WIDTH': 8, 'LINES': 4} #!!!change these to do different versions
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="spi_receive_con_2",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="spi_receive_con_2",
        test_module="test_spi_receive_con_2",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    spi_receive_con_2_runner()
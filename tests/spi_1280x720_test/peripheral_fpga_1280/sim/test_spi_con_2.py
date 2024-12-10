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
async def test_spi_send_con_2(dut):
    """cocotb test for peripheral spi sender"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    dut.trigger_in.value = 0
    await ClockCycles(dut.clk_in, 3, rising = False)

    dut.rst_in.value = 0
    dut.turn_off_cipo_in.value = 0
    await ClockCycles(dut.clk_in, 3, rising = False)

    dut.trigger_in.value = 1
    dut.hcount_in.value = 318
    dut.vcount_in.value = 179
    dut.data_in.value = 0xC4
    await FallingEdge(dut.clk_in)
    dut.trigger_in.value = 0
    dut.data_in.value = 0x00
    await ClockCycles(dut.clk_in, 20, rising=False) 
    dut.hcount_in.value = 319
    dut.vcount_in.value = 179
    dut.trigger_in.value = 1
    dut.data_in.value = 0xB8
    await FallingEdge(dut.clk_in)
    dut.trigger_in.value = 0
    dut.data_in.value - 0x00
    await ClockCycles(dut.clk_in, 30)



def spi_send_con_2_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "spi_send_con_2.sv"]
    build_test_args = ["-Wall"]
    parameters = {'DATA_WIDTH': 8, 'DATA_CLK_PERIOD': 14, 'LINES': 4} #!!!change these to do different versions
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="spi_send_con_2",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="spi_send_con_2",
        test_module="test_spi_con_2",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    spi_send_con_2_runner()
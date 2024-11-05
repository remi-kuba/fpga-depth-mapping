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

# utility function to reverse bits:
def reverse_bits(n,size):
    reversed_n = 0
    for i in range(size):
        reversed_n = (reversed_n << 1) | (n & 1)
        n >>= 1
    return reversed_n

# test spi message:
OG_SPI_RESP_MSG = 0xDEAD_ABCD_1234_BEEF_FEED_FACE_CAFE
#flip them:
SPI_RESP_MSG = reverse_bits(OG_SPI_RESP_MSG,16)

@cocotb.test()
async def test_spi(dut):
    """cocotb test for peripheral spi sender"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    cocotb.start_soon(test_spi_device(dut))
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    dut.trigger_in.value = 0
    dut.data_in.value = 0xBEEF #set in 16 bit input value

def spi_send_con_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "spi_send_con.sv"]
    build_test_args = ["-Wall"]
    parameters = {'DATA_WIDTH': 16, 'DATA_CLK_PERIOD':6} #!!!change these to do different versions
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="spi_send_con",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="spi_send_con",
        test_module="test_spi_send_con",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    spi_send_con_runner()
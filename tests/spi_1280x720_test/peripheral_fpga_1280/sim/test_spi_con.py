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
OG_SPI_RESP_MSG = [0xDEAD, 0xABCD, 0x1234, 0xBEEF, 0xFEED, 0xFACE]
#flip them:
SPI_RESP_MSG = [reverse_bits(msg,16) for msg in OG_SPI_RESP_MSG]

def expected_results(reversed_msg, length):
    res = []
    for i in range(length):
        num = 0
        for j, msg in enumerate(reversed_msg):
            curr_num = (msg & (1 << i)) >> i
            num += (curr_num << j)
        res.append(num)

    return res[::-1]


@cocotb.test()
async def test_spi_send_con(dut):
    """cocotb test for peripheral spi sender"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    dut.trigger_in.value = 0
    await ClockCycles(dut.clk_in, 3, rising = False)

    dut.rst_in.value = 0
    await ClockCycles(dut.clk_in, 3, rising = False)

    dut.trigger_in.value = 1
    for i, msg in enumerate(OG_SPI_RESP_MSG):
        dut.data_in[i].value = msg

    await ClockCycles(dut.clk_in, 1, rising=False) 

    dut.trigger_in.value = 0
    for i in range(6):
        dut.data_in[i].value = 0

    exp = expected_results(OG_SPI_RESP_MSG, 16)
    for i in range(16):
        await ClockCycles(dut.chip_clk_out, 1)
        assert hex(dut.chip_data_out.value) == hex(exp[i]), f"Expected: {hex(exp)}, got: {hex(dut.chip_data_out.value)}"


    await ClockCycles(dut.clk_in, 20, rising=False) 



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
    await ClockCycles(dut.clk_in, 3, rising = False)

    dut.trigger_in.value = 1

    new_msg = [0xCAFE, 0x1293, 0x0942, 0x1892, 0xB9D0, 0xF00D]
    for i, msg in enumerate(new_msg):
        dut.data_in[i].value = msg

    await ClockCycles(dut.clk_in, 1, rising=False) 

    dut.trigger_in.value = 0
    for i in range(6):
        dut.data_in[i].value = 0

    exp = expected_results(new_msg, 16)
    for i in range(16):
        await ClockCycles(dut.chip_clk_out, 1)
        assert hex(dut.chip_data_out.value) == hex(exp[i]), f"Expected: {hex(exp)}, got: {hex(dut.chip_data_out.value)}"

    await ClockCycles(dut.clk_in, 20, rising=False) 



def spi_send_con_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "spi_send_con.sv"]
    build_test_args = ["-Wall"]
    parameters = {'DATA_WIDTH': 16, 'DATA_CLK_PERIOD': 6, 'LINES':6} #!!!change these to do different versions
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
        test_module="test_spi_con",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    spi_send_con_runner()
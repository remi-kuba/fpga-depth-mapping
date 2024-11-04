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
OG_SPI_RESP_MSG = 0xDEAD
#flip them:
SPI_RESP_MSG = reverse_bits(OG_SPI_RESP_MSG,16)

# this module below is a simple "fake" spi module written in Python that we can...
# test our design against.
async def test_spi_device(dut):
  count = 0
  count_max = 16 #change for different sizes
  while True:
    await FallingEdge(dut.chip_sel_out) #listen for falling CS
    dut.chip_data_in.value = (SPI_RESP_MSG>>count)&0x1 #feed in lowest bit
    dut._log.info(f"SPI peripheral Device Sending: {dut.chip_data_in.value}")
    count+=1
    count%=16
    while dut.chip_sel_out.value.integer ==0:
      await RisingEdge(dut.chip_clk_out)
      bit = dut.chip_data_out.value.integer #grab value:
      dut._log.info(f"SPI peripheral Device Receiving: {bit}")
      await FallingEdge(dut.chip_clk_out)
      dut.chip_data_in.value = (SPI_RESP_MSG>>count)&0x1 #feed in lowest bit
      dut._log.info(f"SPI peripheral Device Sending: {dut.chip_data_in.value}")
      count+=1
      count%=16

@cocotb.test()
async def test_a(dut):
    """cocotb test for seven segment controller"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    cocotb.start_soon(test_spi_device(dut))
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    dut.trigger_in.value = 0
    dut.data_in.value = 0xBEEF #set in 16 bit input value
    await ClockCycles(dut.clk_in, 3) #wait three clock cycles
    assert dut.chip_sel_out.value.integer==1, "cs is not 1 on reset!"
    await  FallingEdge(dut.clk_in)
    dut.rst_in.value = 0 #un reset device
    await ClockCycles(dut.clk_in, 3) #wait a few clock cycles
    await  FallingEdge(dut.clk_in)
    dut._log.info("Setting Trigger")
    dut.trigger_in.value = 1
    await FallingEdge(dut.clk_in) # Wait to when the trigger kicks in
    dut._log.info(f"CS: {dut.chip_sel_out.value.integer}")
    assert dut.chip_sel_out.value.integer==0, "cs should be set low after trigger"
    
    await ClockCycles(dut.clk_in, 1,rising=False)
    dut.data_in.value = 0xAAAA # once trigger in is off, don't expect data_in to stay the same!!
    dut.trigger_in.value = 0
    await with_timeout(RisingEdge(dut.data_valid_out),5000,'ns')
    await ReadOnly()
    data_out = dut.data_out.value
    assert hex(data_out) == hex(OG_SPI_RESP_MSG), "Received wrong data"
    await ClockCycles(dut.clk_in, 300)

def spi_con_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "spi_con.sv"]
    build_test_args = ["-Wall"]
    parameters = {'DATA_WIDTH': 16, 'DATA_CLK_PERIOD':15} #!!!change these to do different versions
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="spi_con",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="spi_con",
        test_module="test_spi_con",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    spi_con_runner()
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
from PIL import Image
import random 


async def reset(rst,clk):
    """ Helper function to issue a reset signal to our module """
    rst.value = 1
    await ClockCycles(clk,3)
    rst.value = 0
    await ClockCycles(clk,2)


@cocotb.test()
async def test_arbiter(dut):
    """cocotb test for painter module"""
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    
    await reset(dut.rst_in, dut.clk_in) 

    dut.valid_array = 0b1001 
    dut.data_line = 0xF0FFFF; 
    
    await RisingEdge(dut.clk_in)
    dut.valid_array = 0b0100; 
    dut.data_line = 0xFFF000; 

    await RisingEdge(dut.clk_in)
    dut.valid_array = 0b0000; 
    dut.data_line = 0x0F0000; 

    await ClockCycles(dut.clk_in, 20)

    # await reset(dut.rst_in, dut.clk_in)
    # await send_data(dut, 50)

def painter_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "arbiter.sv"]
    sources += [proj_path / "hdl" / "counter.sv"]
    build_test_args = ["-Wall"]

    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="arbiter",
        always=True,
        build_args=build_test_args,
        parameters = {},
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="arbiter",
        test_module="test_arbiter",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    painter_runner()
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
import numpy as np 

def float_to_binary_float16(float_num):
    # Convert the float to a 16-bit float (half precision)
    float16_value = np.float16(float_num)
    
    # Convert the 16-bit float to its binary representation
    # np.float16() returns a numpy scalar, so we need to convert it to a binary string
    binary_rep = format(float16_value.view(np.uint16), '016b')
    print(float_num, binary_rep)
    return int(binary_rep, 2)

async def reset(rst,clk):
    """ Helper function to issue a reset signal to our module """
    rst.value = 1
    await ClockCycles(clk,3)
    rst.value = 0
    await ClockCycles(clk,2)


@cocotb.test()
async def test_router(dut):
    """cocotb test for painter module"""
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    
    await reset(dut.rst_in, dut.clk_in) 
    dut.data_valid_in = 1; 
    dut.x = float_to_binary_float16(-1)
    dut.y = float_to_binary_float16(-1)
    dut.z = float_to_binary_float16(-1)
    

    await ClockCycles(dut.clk_in, 40)
    # await reset(dut.rst_in, dut.clk_in)
    # await send_data(dut, 50)

def painter_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "pipelined_mvp.sv"]
    sources += [proj_path / "hdl" / "binary16_adder.sv"]
    sources += [proj_path / "hdl" / "binary16_multi.sv"]
    build_test_args = ["-Wall"]

    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="pipelined_mvp",
        always=True,
        build_args=build_test_args,
        parameters = {},
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="pipelined_mvp",
        test_module="test_pipe_mvp",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    painter_runner()
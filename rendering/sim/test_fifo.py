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
async def test_painter(dut):
    """cocotb test for painter module"""
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    # im_output = Image.new('RGB',(320,180))
    # cocotb.start_soon(check_pixels(dut, im_output))
    
    await reset(dut.rst_in, dut.clk_in)

    dut.data_line.value = 0x1111
    dut.data_valid_in = 1
    await RisingEdge(dut.clk_in)
    dut.data_valid_in = 0
    await RisingEdge(dut.clk_in)

    dut.data_line.value = 0x2222
    dut.data_valid_in = 1
    await RisingEdge(dut.clk_in)
    dut.data_valid_in = 0
    await RisingEdge(dut.clk_in)

    dut.data_line.value = 0x3333
    dut.data_valid_in = 1
    await RisingEdge(dut.clk_in)
    dut.data_valid_in = 0
    await RisingEdge(dut.clk_in)

    # dut.rst_in.value = 1 
    await ClockCycles(dut.clk_in, 10) 

    dut.receiver_ready.value = 1
    await RisingEdge(dut.clk_in)
    dut.receiver_ready.value = 0
    await RisingEdge(dut.clk_in)

    dut.receiver_ready.value = 1
    await RisingEdge(dut.clk_in)
    dut.receiver_ready.value = 0
    await RisingEdge(dut.clk_in)

    # dut.rst_in.value = 0 

    # dut.data_valid_in.value = 1 
    # dut.a.value = 150 
    # dut.b.value = 200 

    # await ClockCycles(dut.clk_in, 20)

    # await reset(dut.rst_in, dut.clk_in)
    # await send_data(dut, 50)

def painter_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "fifo.sv"]
    build_test_args = ["-Wall"]

    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="fifo",
        always=True,
        build_args=build_test_args,
        parameters = {"DATA_WIDTH" : 16},
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="fifo",
        test_module="test_fifo",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    painter_runner()
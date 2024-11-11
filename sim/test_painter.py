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

async def send_center(dut, x, y, radius): 
    await RisingEdge(dut.clk_in)
    dut.data_valid_in.value = 1 
    dut.hcount_in.value = x
    dut.vcount_in.value = y
    dut.radius_in.value = radius
    await RisingEdge(dut.clk_in) 
    dut.data_valid_in.value = 0 

async def check_pixels(dut, im_output): 
    while True: 
        await RisingEdge(dut.clk_in)
        if(dut.data_valid_out.value == 1):
            im_output.putpixel((dut.hcount_out.value,dut.vcount_out.value),(0, 0, dut.radius.value * 20))
            print("PIXEL", dut.hcount_out.value, dut.vcount_out.value)

async def send_data(dut, n): 
    await send_center(dut, 20, 30, random.randint(4,8))
    for i in range (n): 
        await RisingEdge(dut.ready_out)
        center_x = random.randint(0, 320-8)
        center_y = random.randint(0, 180-8)
        await send_center(dut, center_x, center_y, random.randint(4,8))

@cocotb.test()
async def test_painter(dut):
    """cocotb test for painter module"""
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    im_output = Image.new('RGB',(320,180))
    cocotb.start_soon(check_pixels(dut, im_output))

    await reset(dut.rst_in, dut.clk_in)
    await send_data(dut, 50)
    # await send_center(dut, 20, 30, 6)
    
    # # create a blank image with dimensions (w,h)


    
    # # write RGB values (r,g,b) [range 0-255] to coordinate (x,y)

    # # save image to a file

    # await RisingEdge(dut.ready_out)
    # await send_center(dut, 70, 70, 4)

    # await ClockCycles(dut.clk_in, 200)
    im_output.save('output.png','PNG')

def painter_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "painter.sv"]
    build_test_args = ["-Wall"]

    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="painter",
        always=True,
        build_args=build_test_args,
        parameters = {},
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="painter",
        test_module="test_painter",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    painter_runner()
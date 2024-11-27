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

# Example usage
float_num = 12.625
binary_rep = float_to_binary_float16(float_num)
print(binary_rep)


async def reset(rst,clk):
    """ Helper function to issue a reset signal to our module """
    rst.value = 1
    await ClockCycles(clk,3)
    rst.value = 0
    await ClockCycles(clk,2)

async def send_center(dut, x, y, radius): 
    await RisingEdge(dut.clk_in)
    dut.data_valid_in.value = 1 
    dut.f_center_x_pos.value = x
    dut.f_center_y_pos.value = y
    dut.f_center_depth.value = 0
    dut.f_radius.value = radius
    await RisingEdge(dut.clk_in) 
    dut.data_valid_in.value = 0 

async def check_pixels(dut, im_output): 
    while True: 
        await RisingEdge(dut.clk_in)
        if(dut.new_pixel_out.value == 1):
            im_output.putpixel((dut.hcount_out.value,dut.vcount_out.value),(0, 0, dut.int_radius.value * 20))
            print("PIXEL", dut.hcount_out.value, dut.vcount_out.value)

async def send_data(dut, n): 
    await send_center(dut, float_to_binary_float16(20), float_to_binary_float16(20), float_to_binary_float16(random.uniform(4,8)))
    for i in range (n): 
        await RisingEdge(dut.ready_out)
        center_x = float_to_binary_float16(random.uniform(0, 320-8))
        center_y = float_to_binary_float16(random.uniform(0, 180-8))
        await send_center(dut, center_x, center_y, float_to_binary_float16(random.uniform(4,8)))

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
    im_output.save('output_r.png','PNG')

def rasterizer_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "rasterizer.sv"]
    sources += [proj_path / "hdl" / "painter.sv"]
    sources += [proj_path / "hdl" / "float_to_int.sv"]
    build_test_args = ["-Wall"]

    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="rasterizer",
        always=True,
        build_args=build_test_args,
        parameters = {},
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="rasterizer",
        test_module="test_rasterizer",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    rasterizer_runner()
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
    dut.f_x_in.value = x
    dut.f_y_in.value = y
    dut.f_z_in.value = 0
    await RisingEdge(dut.clk_in) 
    dut.data_valid_in.value = 0 

async def check_pixels(dut, im_output): 
    while True: 
        await RisingEdge(dut.clk_in)
        if(dut.rasterizer_new_pixel_out.value == 1):
            im_output.putpixel((dut.rasterizer_hcount_out.value,dut.rasterizer_vcount_out.value),(0, 0, 200))
            print(dut.rasterizer_hcount_out.value,dut.rasterizer_vcount_out.value)
            print("PIXEL", dut.rasterizer_hcount_out.value, dut.rasterizer_vcount_out.value)

async def send_data(dut, n): 
    await send_center(dut, float_to_binary_float16(20), float_to_binary_float16(20), float_to_binary_float16(random.uniform(4,8)))
    for i in range (n): 
        await RisingEdge(dut.render_ready)
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
    await send_data(dut, 20)
    # await send_center(dut, 20, 30, 6)
    
    # # create a blank image with dimensions (w,h)


    
    # # write RGB values (r,g,b) [range 0-255] to coordinate (x,y)

    # # save image to a file

    # await RisingEdge(dut.ready_out)
    # await send_center(dut, 70, 70, 4)

    # await ClockCycles(dut.clk_in, 200)
    im_output.save('output_RENDER.png','PNG')
    # await Timer(10, "ms")

def render_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "render.sv"]
    sources += [proj_path / "hdl" / "rasterizer.sv"]
    sources += [proj_path / "hdl" / "projector.sv"]
    sources += [proj_path / "hdl" / "painter.sv"]
    sources += [proj_path / "hdl" / "pixel_manager.sv"]
    sources += [proj_path / "hdl" / "float_to_int.sv"]
    sources += [proj_path / "hdl" / "video_sig_gen.sv"]
    sources += [proj_path / "../simulator/hdl" / "binary16_multi.sv"]

    build_test_args = ["-Wall"]

    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="render",
        always=True,
        build_args=build_test_args,
        parameters = {},
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="render",
        test_module="test_render",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    render_runner()
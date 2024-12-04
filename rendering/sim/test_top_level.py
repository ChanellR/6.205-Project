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
    print("SENDING")
    await RisingEdge(dut.clk_100mhz)
    dut.send_render.value = 1 
    dut.f_x_in.value = x
    dut.f_y_in.value = y
    dut.f_z_in.value = 0
    await RisingEdge(dut.clk_100mhz) 
    print("DONE")
    dut.send_render.value = 0 

async def check_pixels(dut, im_output): 
    while True: 
        await RisingEdge(dut.clk_100mhz)
        if(dut.new_pixel_out.value == 1):

            im_output.putpixel((dut.rendering_inst.rasterizer_hcount_out.value,dut.rendering_inst.rasterizer_vcount_out.value),(0, 0, 200))
            print(dut.rendering_inst.rasterizer_hcount_out.value,dut.rendering_inst.rasterizer_vcount_out.value)
            print("PIXEL", dut.rendering_inst.rasterizer_hcount_out.value, dut.rendering_inst.rasterizer_vcount_out.value)

async def send_data(dut, n): 
    # await send_center(dut, float_to_binary_float16(-7.5), float_to_binary_float16(7.5), float_to_binary_float16(random.uniform(4,8)))
    # await send_center(dut, float_to_binary_float16(-7), float_to_binary_float16(-7), float_to_binary_float16(random.uniform(4,8)))
    await send_center(dut, float_to_binary_float16(0), float_to_binary_float16(0), float_to_binary_float16(random.uniform(4,8)))
    for i in range (n): 
        await RisingEdge(dut.render_ready)
        center_x = float_to_binary_float16(random.uniform(-7.5, 7.5))
        center_y = float_to_binary_float16(random.uniform(-7.5, 7.5))
        await send_center(dut, center_x, center_y, float_to_binary_float16(random.uniform(4,8)))

@cocotb.test()
async def test_painter(dut):
    """cocotb test for painter module"""
    cocotb.start_soon(Clock(dut.clk_100mhz, 10, units="ns").start())
    im_output = Image.new('RGB',(320,180))
    # cocotb.start_soon(check_pixels(dut, im_output))


    await reset(dut.sys_rst, dut.clk_100mhz)
    # await send_data(dut, 1000)
    # await send_center(dut, float_to_binary_float16(-2), float_to_binary_float16(3), float_to_binary_float16(0))
    # await send_center(dut, 0b0100110000000000, 0b0100110000000000, 0b0)
    # await send_center(dut, 20, 30, 6)
    
    # # # create a blank image with dimensions (w,h)

    # dut.prev_vsync = 1; 
    
    # # # write RGB values (r,g,b) [range 0-255] to coordinate (x,y)

    # # # save image to a file

    # # await RisingEdge(dut.ready_out)
    # # await send_center(dut, 70, 70, 4)

    await ClockCycles(dut.clk_100mhz, 200)
    await Timer(40, "ms")
    im_output.save('output_TEST_TOP_LEVEL_FULL.png','PNG')


def render_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))

    sources = [proj_path / "hdl" / "render.sv"]
    sources += [proj_path / "hdl" / "top_level_test.sv"]
    sources += [proj_path / "hdl" / "rasterizer.sv"]
    sources += [proj_path / "hdl" / "projector.sv"]
    sources += [proj_path / "hdl" / "painter.sv"]
    sources += [proj_path / "hdl" / "pixel_manager.sv"]
    sources += [proj_path / "hdl" / "float_to_int.sv"]
    sources += [proj_path / "hdl" / "video_sig_gen.sv"]
    sources += [proj_path / "hdl" / "hdmi_clk_wiz.v"]
    sources += [proj_path / "hdl" / "tmds_encoder.sv"]
    sources += [proj_path / "hdl" / "tmds_serializer.sv"]
    sources += [proj_path / "hdl" / "tm_choice.sv"]
    sources += [proj_path / "hdl" / "counter.sv"]
    sources += [proj_path / "hdl" / "truncate_float.sv"]
    sources += [proj_path / "hdl" / "transform_position.sv"]
    sources += [proj_path / "hdl" / "binary16_adder.sv"]
    sources += [proj_path / "hdl" / "binary16_multi.sv"]
    sources += [proj_path / "hdl" / "binary16_div_pipelined.sv"]

    build_test_args = ["-Wall"]

    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="top_level_test",
        always=True,
        build_args=build_test_args,
        parameters = {},
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="top_level_test",
        test_module="test_top_level",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    render_runner()
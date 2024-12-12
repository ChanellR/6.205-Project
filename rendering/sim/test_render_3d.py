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
    # print(float_num, binary_rep)
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

async def send_center(dut, x, y, z, radius): 
    # print("SENDING")
    await RisingEdge(dut.clk_in)
    dut.data_valid_in.value = 1 
    dut.f_x_in.value = x
    dut.f_y_in.value = y
    dut.f_z_in.value = z
    await RisingEdge(dut.clk_in) 
    # print("DONE")
    dut.data_valid_in.value = 0 

def bin16_to_int(bin16):
    # Ensure the binary string is exactly 16 bits
    
    # Convert the uint16 value to float16
    binary_string = str(bin16)


# Convert the binary16 string to a float
    float_value = np.frombuffer(int(binary_string, 2).to_bytes(2, 'big'), dtype=np.float16)[0]

    # float_value = np.float16(bin16)
    # Return the integer value of the float
    return float_value

async def check_pixels(dut, im_output): 
    while True: 
        await RisingEdge(dut.clk_in)
        if(dut.full_out.value == 1):
            # print(bin16_to_int(dut.rendering_inst.rasterizer_inst.depth_out), "COLOR")
            addr = dut.render_addr_out.value
            y = int(int(str(addr),2) / 320)
            x = addr % 320 
            # print(x)
            # print(y)
            im_output.putpixel((x,y),(0, 0, 200))
            # print(x,y)
            print("PIXEL", x, y)

async def send_data(dut, n): 
    # await send_center(dut, float_to_binary_float16(-7.5), float_to_binary_float16(7.5), float_to_binary_float16(random.uniform(4,8)))
    # await send_center(dut, float_to_binary_float16(-7), float_to_binary_float16(-7), float_to_binary_float16(random.uniform(4,8)))
    await send_center(dut, float_to_binary_float16(0), float_to_binary_float16(0), float_to_binary_float16(random.uniform(4,8)))
    for i in range (n): 
        await RisingEdge(dut.render_ready)
        center_x = float_to_binary_float16(random.uniform(-8, 8))
        center_y = float_to_binary_float16(random.uniform(-8, 8))
        await send_center(dut, center_x, center_y, float_to_binary_float16(random.uniform(-4,4)), 0)


async def send_cube(dut, n): 
    points = sort_points_by_z(generate_cube_points_edge(num_points_per_edge=int(n/12), side_length=10))
    # await send_center(dut, float_to_binary_float16(-7.5), float_to_binary_float16(7.5), float_to_binary_float16(random.uniform(4,8)))
    # await send_center(dut, float_to_binary_float16(-7), float_to_binary_float16(-7), float_to_binary_float16(random.uniform(4,8)))
    # await send_center(dut, float_to_binary_float16(0), float_to_binary_float16(0), float_to_binary_float16(0), float_to_binary_float16(random.uniform(4,8)))
    for i in range (len(points)): 
        while dut.full_out.value == 1:
            await RisingEdge(dut.clk_in)
        await RisingEdge(dut.clk_in)
        center_x = float_to_binary_float16(points[i][0])
        center_y = float_to_binary_float16(points[i][1])
        await send_center(dut, center_x, center_y, float_to_binary_float16(points[i][2]), float_to_binary_float16(0))
        

def sort_points_by_z(points):
  """
  Sort a list of points based on the z-coordinate in decreasing order.
  
  Parameters:
  - points: A list of tuples representing points (x, y, z).
  
  Returns:
  - A sorted list of points with the highest z-coordinate first.
  """
  return sorted(points, key=lambda point: point[2], reverse=True)

# async def send_data(dut, n): 
    
def generate_cube_points_edge(num_points_per_edge=50, side_length=2):
    # Half side length to ensure the cube is centered at the origin
    half_side = side_length / 2
    
    # Define the 8 vertices of the cube based on the side length
    vertices = np.array([[-half_side, -half_side, -half_side],
                         [ half_side, -half_side, -half_side],
                         [ half_side,  half_side, -half_side],
                         [-half_side,  half_side, -half_side],
                         [-half_side, -half_side,  half_side],
                         [ half_side, -half_side,  half_side],
                         [ half_side,  half_side,  half_side],
                         [-half_side,  half_side,  half_side]])
    
    # Define the edges of the cube by specifying pairs of vertices
    edges = [
        (0, 1), (1, 2), (2, 3), (3, 0),  # Bottom face edges
        (4, 5), (5, 6), (6, 7), (7, 4),  # Top face edges
        (0, 4), (1, 5), (2, 6), (3, 7)   # Vertical edges
    ]
    
    # Generate points along each edge
    points = []
    for (start_idx, end_idx) in edges:
        start_point = vertices[start_idx]
        end_point = vertices[end_idx]
        
        # Generate `num_points_per_edge` points between the two endpoints
        for t in np.linspace(0, 1, num_points_per_edge):
            point = (1 - t) * start_point + t * end_point
            points.append(point)
    
    return np.array(points)

@cocotb.test()
async def test_painter(dut):
    """cocotb test for painter module"""
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    im_output = Image.new('RGB',(320,180))
    #  cocotb.start_soon(check_pixels(dut, im_output))

    await reset(dut.rst_in, dut.clk_in)
    # await send_cube(dut, 24) 
    # await send_center(dut, float_to_binary_float16(-2), float_to_binary_float16(3), float_to_binary_float16(3), float_to_binary_float16(1))
    await send_center(dut, float_to_binary_float16(-3), float_to_binary_float16(3), float_to_binary_float16(2), float_to_binary_float16(1))
    # await send_center(dut, 0b0100110000000000, 0b0100110000000000, 0b0)
    # await send_center(dut, 20, 30, 6)
    
    # # # create a blank image with dimensions (w,h)

    # dut.prev_vsync = 1; 
    
    # # # write RGB values (r,g,b) [range 0-255] to coordinate (x,y)

    # # # save image to a file

    # # await RisingEdge(dut.ready_out)
    # # await send_center(dut, 70, 70, 4)

    await ClockCycles(dut.clk_in, 200)
    # await Timer(4, "ms")
    im_output.save('output_TEST_TOP_LEVEL_PARA.png','PNG')


def render_runner():
    """Simulate the counter using the Python runner."""
    
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))

    sources = [proj_path / "hdl" / "render_3d.sv"]
    sources += [proj_path / "hdl" / "rasterizer.sv"]
    sources += [proj_path / "hdl" / "arbiter.sv"]
    sources += [proj_path / "hdl" / "bus_driver.sv"]
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
    sources += [proj_path / "hdl" / "pipelined_mvp.sv"]
    sources += [proj_path / "hdl" / "fifo.sv"]
    sources += [proj_path / "hdl" / "router.sv"]
    sources += [proj_path / "hdl" / "depth_buffer.sv"]
    sources += [proj_path / "hdl" / "xilinx_true_dual_port_read_first_2_clock_ram.v"]

    build_test_args = ["-Wall"]

    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="render_3d",
        always=True,
        build_args=build_test_args,
        parameters = {},
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="render_3d",
        test_module="test_render_3d",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    render_runner()
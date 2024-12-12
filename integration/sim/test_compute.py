import cocotb
import os
import random
import sys
from math import log
import logging
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly, with_timeout
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner
import numpy as np
from test_binary16_adder import *
from numpy import pi

H = 2.0
BOUNDS = (2.0, 2.0) # TODO: Implement properly on both sides
TIME_STEP = 1/30 # 0.1-0.3, higher then instability grows in the velocities at > 50 particle range
TARGET_DENSITY = 2.0
PRESSURE_CONST = 8.0
KERNEL_COEFF = 1 / (pi * (H**4) / 6)
DIV_KERNEL_COEFF = 12 / (pi * H**4)

MODULE = "compute"
H_rep, TARGET_DENSITY_rep, PRESSURE_CONST_rep, TIME_STEP_rep = rep(H), rep(TARGET_DENSITY), rep(PRESSURE_CONST), rep(TIME_STEP)
KERNEL_COEFF_rep, DIV_KERNEL_COEFF_rep = rep(KERNEL_COEFF), rep(DIV_KERNEL_COEFF)
PARAMETERS = {
    "H": H_rep, 
    "TIME_STEP": TIME_STEP_rep, 
    # "PARTICLE_COUNT": N, 
    "DIMS": 2,
    "BOUND": rep(BOUNDS[0]) << 16 | rep(BOUNDS[1]),
    "TARGET_DENSITY": TARGET_DENSITY_rep,
    "PRESSURE_CONST": PRESSURE_CONST_rep,
    "KERNEL_COEFF": KERNEL_COEFF_rep,
    "DIV_KERNEL_COEFF": DIV_KERNEL_COEFF_rep,
}
SOURCES = [f"{MODULE}.sv", 
           "binary16_adder.sv", 
           "binary16_multi.sv", 
           "calc_kernel.sv", 
           "calc_distance.sv", 
           "binary16_sqrt.sv",
           "binary16_div.sv",
           "binary16_div_pipelined.sv",
           "calc_spiky_kernel.sv"
]

@cocotb.test
async def test(dut):
    """Test binary16_multi with some 16-bit floating point numbers"""
    dut._log.info("Starting binary16_multi test...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk_in, 3)
    dut.rst.value = 0
    
    test_vectors = []
    
    print("Generating test vectors...")
    
    positions = [
        (0.0, 0.0),
        (1.0, 1.0),
        (2.0, 2.0),
        ]
    recips = [0x362f, 0x350b, 0x362f]
    pressures = [0x38b0, 0x3cb0, 0x38b0]
    
    # (x_i, y_i, x_j, y_j, pressure_i, pressure_j, rho_recip_j)
    for i, (x_i, y_i) in enumerate(positions):
        for j, (x_j, y_j) in enumerate(positions):
            pressure_i = pressures[i]
            pressure_j = pressures[j]
            rho_recip_j = recips[j]
            task_data = (
                (rep(x_i) & 0xFFFF) << 16*6 |
                (rep(y_i) & 0xFFFF) << 16*5 |
                (rep(x_j) & 0xFFFF) << 16*4 |
                (rep(y_j) & 0xFFFF) << 16*3 |
                (pressure_i & 0xFFFF) << 16*2 |
                (pressure_j & 0xFFFF) << 16*1 |
                (rho_recip_j & 0xFFFF) << 16*0
            )
            test_vectors.append((task_data, 0))
    
    outputs = []
    for task_data, type in test_vectors:
        dut.data_in.value = int(task_data)
        dut.task_type.value = int(type)
        dut.valid_task.value = 1
        await ClockCycles(dut.clk_in, 1)
        dut.valid_task.value = 0
        await with_timeout(RisingEdge(dut.data_valid_out), 10*80, 'ns')
        await Timer(1, 'ns')
        dut._log.info(f"data:{hex(task_data)}: {(dut.data_out.value, half(dut.data_out.value))}")
    
    # MODULE_LENGTH = 50
    # dut.data_valid_in.value = 0
    # for _ in range(MODULE_LENGTH):
    #     await ClockCycles(dut.clk_in, 1)
    #     if dut.data_valid_out.value == 1:
    #         value = dut.result.value
    #         outputs.append(value)
            
    await ClockCycles(dut.clk_in, 3)
    # dut._log.info(f"Outputs: {[half(o) for o in outputs]}")
    
def test_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / s for s in SOURCES]
    build_test_args = ["-Wall"]
    parameters = PARAMETERS #setting parameter to a short amount (for testing)
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=f"{MODULE}",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel=f"{MODULE}",
        hdl_toplevel_lang=hdl_toplevel_lang, # check this
        test_module=f"test_{MODULE}",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    test_runner()
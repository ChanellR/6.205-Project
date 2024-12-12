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
from test_binary16_adder import rep, half, float_to_binary16_int_rep

MODULE = "particle_updater"
PARAMETERS = {"TIME_STEP": rep(1.0)}
SOURCES = [f"{MODULE}.sv",
           "binary16_adder.sv",
           "binary16_multi.sv",
]


@cocotb.test
async def test_a(dut):
    
    # (x, y)
    particle_pos = (rep(0.0), rep(0.0))
    particle_vel = (rep(1.0), rep(0.0))
    force = (rep(1.0), rep(0.0))
    density_recip = rep(0.5)
    
    async def mem_sim(dut):
        memory = [
            particle_pos[0] << 16 | particle_pos[1],
            particle_vel[0] << 16 | particle_vel[1],
        ]
        output_pipe = [0, 0]
        while True:
            await FallingEdge(dut.clk_in)
            output_pipe = output_pipe[1:] + [memory[dut.addr_out.value]]
            dut.mem_in.value = output_pipe[0]
            if dut.mem_write_enable.value:
                memory[dut.addr_out.value] = dut.mem_out.value
    
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())   
    cocotb.start_soon(mem_sim(dut))
     
    dut.rst.value = 1
    await ClockCycles(dut.clk_in, 2) #wait three clock cycles
    dut.rst.value = 0
    # await FallingEdge(dut.clk_in)
    
    dut.accumulator_in.value = (force[0] << 16*2) | (force[1] << 16) | density_recip
    dut.trigger_update.value = 1
    dut.particle_idx.value = 0
    await ClockCycles(dut.clk_in, 1)
      
    dut.trigger_update.value = 0
     
    
    await with_timeout(RisingEdge(dut.mem_write_enable), 10*50,'ns')
    await Timer(1, 'ns')
    velocity = (half(dut.mem_out.value >> 16), half(dut.mem_out.value & 0xFFFF))
    await ClockCycles(dut.clk_in, 1)
    position = (half(dut.mem_out.value >> 16), half(dut.mem_out.value & 0xFFFF))
    dut._log.info(f"Position: {position}")
    dut._log.info(f"Velocity: {velocity}")
    await ReadOnly()

    
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
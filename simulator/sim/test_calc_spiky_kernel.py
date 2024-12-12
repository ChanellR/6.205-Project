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
from test_funcs import *
from numpy import pi

MODULE = "calc_spiky_kernel"
PARAMETERS = {} # utilizing H = 0.35f
SOURCES = [f"{MODULE}.sv", "binary16_adder.sv", "binary16_multi.sv"]

@cocotb.test
async def test_a(dut):
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut._log.info("Holding reset...")
    
    dut.rst.value = 1
    await ClockCycles(dut.clk_in, 3) #wait three clock cycles
    dut.rst.value = 0
    
    test_vectors = []
    H = 0.35

    for i in range(5):
        r = float32_to_binary16(random.uniform(0, 1.0))
        r_rep = rep(r)
        expected = (r - H)**2 * (6 / (pi * H**4)) if r <= H else 0
        deriv_expected = -(2 * (r - H) * (6 / (pi * H**4))) if r <= H else 0
        dut._log.info(f"r={r}, r_rep={r_rep}, {i%2} expected={(hex(rep(expected)), expected),} deriv_expected={(hex(rep(deriv_expected)), deriv_expected)}")
        test_vectors.append((r_rep, i % 2, expected))
    
    outputs = []
    # New inputs every clock cycle
    dut.data_valid_in.value = 1
    dut.is_density_task.value = 1
    for r, is_density, expected in test_vectors:
        dut.r.value = int(r)
        await ClockCycles(dut.clk_in, 1)
        if dut.data_valid_out.value == 1:
            value = dut.result.value
            outputs.append(value)
        # dut._log.info(f"r={half(r)} - {is_density=} - expected {(hex(rep(expected)),expected)}")
    
    dut.data_valid_in.value = 0
    for _ in range(16):
        await ClockCycles(dut.clk_in, 1)
        if dut.data_valid_out.value == 1:
            value = dut.result.value
            outputs.append(value)
            
    await ClockCycles(dut.clk_in, len(test_vectors) + 12)
    dut._log.info(f"Outputs: {[(half(o), o) for o in outputs]}")

    
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
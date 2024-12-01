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
from test_binary16_adder import half, float32_to_binary16, float_to_binary16_int_rep

MODULE = "calc_density"
H = 2.0
H_rep = eval(f"0b{float32_to_binary16(H).view(np.uint16):016b}")
PARAMETERS = {"H": H_rep}
SOURCES = [f"{MODULE}.sv", "binary16_sqrt.sv", "binary16_multi.sv", "binary16_adder.sv"]

@cocotb.test
async def test(dut):
    dut._log.info(f"Starting {MODULE} test...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    
    dut.rst.value = 1
    await ClockCycles(dut.clk_in, 3)
    dut.rst.value = 0
    
    pairs = [(0.0, 0.0), (0.0, 1.0), (0.0, 2.0), (0.0, 3.0)]
    test_vectors = []

    for a, b in pairs:
    # for _ in range(5):
        # a = random.uniform(-1.0, 1.0)
        # b = random.uniform(-1.0, 1.0)
        r_i = float32_to_binary16(a)
        r_j = float32_to_binary16(b)
        r_i_rep = eval(f"0b{r_i.view(np.uint16):016b}")
        r_j_rep = eval(f"0b{r_j.view(np.uint16):016b}")
        expected = max([float32_to_binary16(H) - abs(r_i - r_j), 0]) # type: ignore
        # expected = max([float32_to_binary16(H) - abs(a - b), 0])
        val = (r_i-r_j)**2
        # dut._log.info(f"r_i-r_j={np.float16(float(r_i-r_j)).view(np.uint16):016b}, {r_i-r_j}")
        # dut._log.info(f"(r_i-r_j)^2={np.float16(float(val)).view(np.uint16):016b}, {val}")
        dut._log.info(f"r_i={r_i}, r_j={r_j}: expected {expected}, {np.float16(float(expected)).view(np.uint16):016b}")
        test_vectors.append((r_i_rep, r_j_rep, expected))

    # for r_i, r_j, expected in test_vectors:
    #     dut.r_i.value = int(r_i)
    #     dut.r_j.value = int(r_j)
    #     dut.data_valid_in.value = 1
    #     await ClockCycles(dut.clk_in, 1)
    #     dut.data_valid_in.value = 0
    #     await RisingEdge(dut.data_valid_out)
    #     value = dut.result.value
    #     print(f"r_i={half(r_i)}, r_j={half(r_j)}: expected {expected}, got {value,half(value)}")

    # await ClockCycles(dut.clk_in, 4)
    
    outputs = []
    # New inputs every clock cycle
    dut.data_valid_in.value = 1
    for a, b, expected_sum in test_vectors:
        dut.r_i.value = int(a)
        dut.r_j.value = int(b)
        await ClockCycles(dut.clk_in, 1)
        if dut.data_valid_out.value == 1:
            value = dut.result.value
            outputs.append(value)
        # dut._log.info(f"a={half(a)}, b={half(b)}: expected {expected_sum}")
    
    dut.data_valid_in.value = 0
    while len(outputs) < len(test_vectors):
        await ClockCycles(dut.clk_in, 1)
        if dut.data_valid_out.value == 1:
            value = dut.result.value
            outputs.append(value)
            
    await ClockCycles(dut.clk_in, 3)
    dut._log.info(f"Outputs: {[half(o) for o in outputs]}")
    
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
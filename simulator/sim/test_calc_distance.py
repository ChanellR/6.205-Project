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

MODULE = "calc_distance"
H = 2.0
H_rep = eval(f"0b{float32_to_binary16(H).view(np.uint16):016b}")
PARAMETERS = {"H": H_rep, "DIM": 2}
SOURCES = [f"{MODULE}.sv", "binary16_sqrt.sv", "binary16_multi.sv", "binary16_adder.sv"]

@cocotb.test
async def test(dut):
    dut._log.info(f"Starting {MODULE} test...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    
    def kernel(distance, h):
        return max([float32_to_binary16(h) - distance, 0])
    
    dut.rst.value = 1
    await ClockCycles(dut.clk_in, 3)
    dut.rst.value = 0
    
    points = [
        (0.0, 0.0),
        (1.0, 1.0),
        (2.0, 2.0),
        (3.0, 3.0)
    ]
    
    pairs = [(points[0], points[j]) for j in range(0, len(points))]
    
    test_vectors = []

    for a, b in pairs:
    # for _ in range(5):
        # a = random.uniform(-1.0, 1.0)
        # b = random.uniform(-1.0, 1.0)
        # r_i = float32_to_binary16(a) 
        # r_j = float32_to_binary16(b)
        
        # r_i_rep = eval(f"0b{r_i.view(np.uint16):016b}")
        # r_j_rep = eval(f"0b{r_j.view(np.uint16):016b}")
        r_i_rep = eval(f"0b{float_to_binary16_int_rep(a[0]):016b}{float_to_binary16_int_rep(a[1]):016b}")
        r_j_rep = eval(f"0b{float_to_binary16_int_rep(b[0]):016b}{float_to_binary16_int_rep(b[1]):016b}")
        r_i = a
        r_j = b
        distance = np.linalg.norm(np.array(r_i) - np.array(r_j))
        # expected = max([float32_to_binary16(H) - distance, 0]) # type: ignore
        expected = distance
        # expected = max([float32_to_binary16(H) - abs(a - b), 0])
        # val = ((r_i[0] - r_j[0])**2 + (r_i[1] - r_j[1])**2)**0.5
        # dut._log.info(f"|r_i-r_j|={float_to_binary16_int_rep(distance):016b}, {distance}")
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
    for a, b, _ in test_vectors:
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
    
    converted_outputs = [(hex(int(o)), half(o)) for o in outputs]
    # expected_outputs = [e for _, _, e in test_vectors]
    
    dut._log.info(f"Outputs: {converted_outputs}")
    # dut._log.info(f"Sum: {sum(converted_outputs)}")
    # dut._log.info(f"Expected: {expected_outputs}")
    # dut._log.info(f"Expected sum: {sum(expected_outputs)}")
    
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
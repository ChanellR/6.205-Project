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

def float32_to_binary16(val):
    """Convert a 32-bit floating point number to a 32-bit binary number."""
    return np.float16(val)

def half(val):
    """Convert a 16-bit binary number to a half-precision floating point number."""
    sign = (val >> 15) & 0x1
    exponent = (val >> 10) & 0x1F
    fraction = val & 0x3FF

    if exponent == 0:
        if fraction == 0:
            return 0.0
        else:
            return (-1)**sign * 2**(-14) * (fraction / 1024)
    elif exponent == 0x1F:
        if fraction == 0:
            return float('inf') if sign == 0 else float('-inf')
        else:
            return float('nan')
    else:
        return (-1)**sign * 2**(exponent - 15) * (1 + fraction / 1024)
    
MODULE = "binary16_sqrt"
PARAMETERS = {}
SOURCES = [f"{MODULE}.sv"]

@cocotb.test
async def test(dut):
    f"""Test {MODULE} with some 16-bit floating point numbers"""
    dut._log.info(f"Starting {MODULE} test...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk_in, 3)
    dut.rst.value = 0
    
    test_vectors = []

    dut._log.info("Generating test vectors...")
    for n in range(10):
        n = float32_to_binary16(random.uniform(0, 500.0))
        # n = float32_to_binary16(400.75)
        # n = float32_to_binary16(n)
        n_rep = eval(f"0b{n.view(np.uint16):016b}")

        n_mantissa = n_rep & 0x3FF | 0x400
        if n_rep & 0x0400:
            n_mantissa >>= 1
        mantissa_sqrt = int((n_mantissa << 11) ** 0.5)
        expected = n ** 0.5

        dut._log.info(f"n: {n.view(np.uint16):016b},expected: {expected.view(np.uint16):016b}, mantissa_sqrt: {mantissa_sqrt:011b}")
        test_vectors.append((n_rep, expected))
        
    # for n, expected in test_vectors:
    #     dut.n.value = int(n)
    #     dut.data_valid_in.value = 1
    #     await ClockCycles(dut.clk_in, 1)
    #     dut.data_valid_in.value = 0
    #     await RisingEdge(dut.data_valid_out)
    #     await Timer(1, 'ns')
    #     value = dut.result.value
    #     dut._log.info(f"n={half(n)}, expected {expected}, got {value,half(value)}")
        
    # await ClockCycles(dut.clk_in, 3)
    
    outputs = []
    # New inputs every clock cycle
    dut.data_valid_in.value = 1
    for n, expected_sum in test_vectors:
        dut.n.value = int(n)
        # dut.b.value = int(b)
        await ClockCycles(dut.clk_in, 1)
        if dut.data_valid_out.value == 1:
            value = dut.result.value
            outputs.append(value)
        dut._log.info(f"a={half(n)}, expected {expected_sum}")
    
    dut.data_valid_in.value = 0
    for _ in range(13):
        await ClockCycles(dut.clk_in, 1)
        if dut.data_valid_out.value == 1:
            value = dut.result.value
            outputs.append(value)
            
    # await ClockCycles(dut.clk_in, len(test_vectors) + 12 + 3)
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
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
    
MODULE = "binary16_div"
PARAMETERS = {}
SOURCES = [f"{MODULE}.sv"]

@cocotb.test
async def test(dut):
    """Test binary16_div with some 16-bit floating point numbers"""
    dut._log.info("Starting binary16_div test...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk_in, 3)
    dut.rst.value = 0
    
    test_vectors = []
    
    print("Generating test vectors...")
    for _ in range(10):
        a = float32_to_binary16(random.uniform(-10.0, 10.0))
        b = float32_to_binary16(random.uniform(-10.0, 10.0))

        a_rep = eval(f"0b{a.view(np.uint16):016b}")
        b_rep = eval(f"0b{b.view(np.uint16):016b}")

        a_mantissa = a_rep & 0x3FF | 0x400
        b_mantissa = b_rep & 0x3FF | 0x400
        mantissa_quotient = (a_mantissa << 11) // b_mantissa
        expected = a / b

        print(f"a: {a.view(np.uint16):016b}, b: {b.view(np.uint16):016b}, expected: {expected.view(np.uint16):016b}, mantissa_quotient: {mantissa_quotient:022b}")
        test_vectors.append((a_rep, b_rep, expected))

    for a, b, expected in test_vectors:
        dut.a.value = int(a)
        dut.b.value = int(b)
        dut.data_valid_in.value = 1
        await ClockCycles(dut.clk_in, 1)
        dut.data_valid_in.value = 0
        await RisingEdge(dut.data_valid_out)
        value = dut.result.value
        print(f"a={half(a)}, b={half(b)}: expected {expected}, got {value,half(value)}")

    await ClockCycles(dut.clk_in, 4)
    
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
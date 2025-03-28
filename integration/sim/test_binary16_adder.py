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

def rep(val):
    return eval(f"0b{float32_to_binary16(val).view(np.uint16):016b}")

def float32_to_binary16(val):
    """Convert a 32-bit floating point number to a binary16 value."""
    return np.float16(val)

def half(val):
    """Convert a binary16 number to a floating point number."""
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
    
def float_to_binary16_int_rep(val):
    return eval(f"0b{float32_to_binary16(val).view(np.uint16):016b}")

MODULE = "binary16_adder"
PARAMETERS = {}
SOURCES = [f"{MODULE}.sv"]

@cocotb.test
async def test(dut):
    """Test binary16_adder with some 16-bit floating point numbers"""
    dut._log.info("Starting binary16_adder test...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    
    dut.rst.value = 1
    await ClockCycles(dut.clk_in, 3)
    dut.rst.value = 0
    
    test_vectors = []

    for _ in range(5):
        a = float32_to_binary16(random.uniform(-10.0, 10.0))
        b = float32_to_binary16(random.uniform(-10.0, 10.0))
        # a = float32_to_binary16(3.1)
        # b = float32_to_binary16(2.5)
        a_rep = eval(f"0b{a.view(np.uint16):016b}")
        b_rep = eval(f"0b{b.view(np.uint16):016b}")
        expected_sum = a + b
        dut._log.info(f"a={hex(a.view(np.uint16))}, b={hex(b.view(np.uint16))}, res={hex(expected_sum.view(np.uint16))}")
        test_vectors.append((a_rep, b_rep, expected_sum))

    # New input after every completion
    # for a, b, expected_sum in test_vectors:
    #     dut.a.value = int(a)
    #     dut.b.value = int(b)
    #     dut.data_valid_in.value = 1
    #     await ClockCycles(dut.clk_in, 1)
    #     dut.data_valid_in.value = 0
    #     await RisingEdge(dut.data_valid_out)
    #     value = dut.result.value
    #     print(f"a={half(a)}, b={half(b)}: expected {expected_sum}, got {value,half(value)}")
    # await ClockCycles(dut.clk_in, 3)

    outputs = []
    # New inputs every clock cycle
    dut.data_valid_in.value = 1
    for a, b, expected_sum in test_vectors:
        dut.a.value = int(a)
        dut.b.value = int(b)
        await ClockCycles(dut.clk_in, 1)
        if dut.data_valid_out.value == 1:
            value = dut.result.value
            outputs.append(value)
        dut._log.info(f"a={half(a)}, b={half(b)}: expected {float32_to_binary16(expected_sum).view(np.uint16):016b}, {expected_sum}")
    
    dut.data_valid_in.value = 0
    for _ in range(6):
        await ClockCycles(dut.clk_in, 1)
        if dut.data_valid_out.value == 1:
            value = dut.result.value
            outputs.append(value)
            
    await ClockCycles(dut.clk_in, len(test_vectors) + 6 + 3)
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
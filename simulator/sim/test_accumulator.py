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
from test_binary16_adder import half, float32_to_binary16, float_to_binary16_int_rep

MODULE = "accumulator"
PARAMETERS = {}
SOURCES = [f"{MODULE}.sv", "binary16_adder.sv"]

@cocotb.test
async def test_a(dut):
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut._log.info("Holding reset...")
    dut.rst.value = 1
    await ClockCycles(dut.clk_in, 3) #wait three clock cycles
    dut.rst.value = 0
    
    test_vectors = []
    for _ in range(8):
        test_vectors.append(random.uniform(-10.0, 10.0))
    
    dut.is_density_task.value = 1
    dut.terms_in_flight.value = 1
    dut.main_index.value = 0
    for a in test_vectors:
        dut.data_in.value = float_to_binary16_int_rep(a)
        dut.data_valid_in.value = 1
        await ClockCycles(dut.clk_in, 1)

    dut.data_valid_in.value = 0
    dut.terms_in_flight.value = 0

    await with_timeout(RisingEdge(dut.data_valid_out),5000,'ns')
    dut._log.info(f"Got {half(dut.data_out.value)} expected {sum(test_vectors)}")
    await ClockCycles(dut.clk_in, 4)
    
    dut.req_index.value = 0
    await ClockCycles(dut.clk_in, 3)
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
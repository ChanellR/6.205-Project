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

MODULE = "renderer"
PARAMETERS = {}
SOURCES = [f"{MODULE}.sv", 
            "binary16_div_pipelined.sv",
            "binary16_adder.sv",
            "binary16_multi.sv",
            "truncate_float.sv",
            "tmds_encoder.sv",
            "tmds_serializer.sv",
            "tm_choice.sv",
            "video_sig_gen.sv",
            "transform_position.sv",
            "xilinx_true_dual_port_read_first_2_clock_ram.v",
]

@cocotb.test
async def test_a(dut):
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_pixel, 10, units="ns").start())
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_pixel, 3) #wait three clock cycles
    dut.rst_in.value = 0
    await RisingEdge(dut.new_frame)
    await ClockCycles(dut.clk_pixel, 3)
    # await with_timeout(RisingEdge(dut.data_valid_out),5000,'ns')
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
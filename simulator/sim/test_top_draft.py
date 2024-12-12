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
from test_binary16_adder import half
import pygame

MODULE = "top_draft"
PARAMETERS = {}
SOURCES = [
    f"{MODULE}.sv", 
    "binary16_adder.sv",
    "binary16_multi.sv", 
    "xilinx_true_dual_port_read_first_2_clock_ram.v",
    "reader.sv",
    "updater.sv",
    "pulser.sv",
    "debouncer.sv",
]

async def generate_clock(clock_wire, fmhz=100):
    T_half = round(((1/(fmhz*1e6))/1e-9)/2,3)
    while True:
        clock_wire.value = 0
        await Timer(T_half,units="ns")
        clock_wire.value = 1
        await Timer(T_half,units="ns")

async def flash_sig(clk, sig): 
    sig.value = 1
    await RisingEdge(clk)   
    sig.value = 0    
    await RisingEdge(clk) 

async def wait(clk,cycles):
    for _ in range(cycles): await RisingEdge(clk) 

async def osc_sig(clk, sig):
    sig.value = 1
    await wait(clk, rr(1,35))
    sig.value = 0;
    await wait(clk, rr(1,35))
    
def set(dut,sig_val_pairs): 
    if type(sig_val_pairs) != list: 
        exec(f"dut.{sig_val_pairs[0]}.value = {sig_val_pairs[1]}")
    else:
        for sig,val in sig_val_pairs: exec(f"dut.{sig}.value = {val}")

def get(dut,sigs): 
    if type(sigs) != list: return exec(f"dut.{sigs}.value")
    vals = []
    local_scope = {"dut":dut}
    for sig in sigs:
        exec(f"val = int(dut.{sig}.value)", local_scope)
        vals.append(local_scope["val"])
    return vals

@cocotb.test
async def top_test(dut):
    
    # Initialize Pygame
    pygame.init()
    screen = pygame.display.set_mode((800, 600))
    pygame.display.set_caption("Particle Position")

    # Function to draw the particle
    def draw_particle(screen, position):
        screen.fill((255, 255, 255))  # Clear screen with black
        pygame.draw.circle(screen, (0, 0, 255), position, 10)  # Draw particle as a red circle
        pygame.display.flip()

    # Convert float position to screen coordinates
    def float_to_screen_coords(float_position):
        x = 800 / 2  # Scale and wrap around screen width
        y = 300 + (300 * -(float_position / 10))  # Scale and wrap around screen height
        return (x, y)

    clk = dut.clk_100mhz
    
    await cocotb.start(generate_clock(clk,100))
    set(dut, [("btn",0) , ("sw",0)])
    await flash_sig(clk, dut.btn[0])
    
    step = 0
    float_position = 0.0
    running = True
    while running:
        for event in pygame.event.get():
            
            if event.type == pygame.KEYDOWN:
                if event.key == pygame.K_SPACE:
                    await flash_sig(clk, dut.btn[1])
                    await with_timeout(RisingEdge(dut.update_finished), 10*40, "ns")
                    hex_velocity = dut.dinb.value
                    float_velocity = half(hex_velocity)
                    await with_timeout(FallingEdge(dut.update_finished), 10*40, "ns")
                    hex_position = dut.dinb.value
                    float_position = half(hex_position)
                    dut._log.info(f"step {step} -- position: {hex_position, float_position} -- velocity: {hex_velocity, float_velocity}")
                    step += 1
                    
            if event.type == pygame.QUIT:
                running = False
                
        screen_position = float_to_screen_coords(float_position)
        draw_particle(screen, screen_position)
        
    await wait(clk, 5)
    pygame.quit()

    
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
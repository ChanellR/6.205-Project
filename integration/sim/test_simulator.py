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
from test_funcs import half, float32_to_binary16, float_to_binary16_int_rep, rep
from sph_engine import *
import pygame

MODULE = "simulator"

# H = 0.35
# H = 2.0
# BOUNDS = (2.0, 2.0) # TODO: Implement properly on both sides
# TIME_STEP = 1/60 # 0.1-0.3, higher then instability grows in the velocities at > 50 particle range
# TARGET_DENSITY = 55.0
# PRESSURE_CONST = 500.0

BOUNDS = (2.0, 2.0) # TODO: Implement properly on both sides
DAMPING_FACTOR = 0.55

H = 0.25
KERNEL_COEFF = 1 / (pi * (H**4) / 6)
DIV_KERENEL_COEFF = 12 / (pi * H**4)
print(f"KERNEL_COEFF: {KERNEL_COEFF}, DIV_KERENEL_COEFF: {DIV_KERENEL_COEFF}")
TIME_STEP = 1/30 # 0.1-0.3, higher then instability grows in the velocities at > 50 particle range
TARGET_DENSITY = 2.0
PRESSURE_CONST = 8.0

positions = [(random.uniform(0, 1), random.uniform(0, 1)) for _ in range(64)]
# positions = [
#     (0.0, 0.0),
#     (1.0, 1.0),
#     (2.0, 2.0),
#     # (3.0, 3.0)
# ]
N = len(positions)

velocities = [(0.0, 0.0) for _ in range(len(positions))]

# Convert positions and velocities to binary16 representations
positions_binary16 = [(float_to_binary16_int_rep(pos[0]), float_to_binary16_int_rep(pos[1])) for pos in positions]
velocities_binary16 = [(float_to_binary16_int_rep(vel[0]), float_to_binary16_int_rep(vel[1])) for vel in velocities]

# Write the binary16 values to ../data/particle.mem
with open("/mnt/c/Users/morvi/Documents/Classes/Fall24/6.205/project/simulator/data/particle.mem", "w") as mem_file:
    for (x, y), (v_x, v_y) in zip(positions_binary16, velocities_binary16):
        mem_file.write(f"{x:04x}{y:04x}{v_x:04x}{v_y:04x}\n")
        
particles = [Particle(np.array(p), np.array(v)) for p, v in zip(positions, velocities)]
engine = SPH_Engine(
    particles, 
    mass=1.0, 
    time_step=TIME_STEP, 
    h=H, 
    kernel=smoothing_kernel,
    kernel_gradient=smoothing_kernel_gradient,
    target_density=TARGET_DENSITY, 
    pressure_coeff=PRESSURE_CONST, 
    gravitational_constant=-12,
    collision_damping=DAMPING_FACTOR, 
    bounds=BOUNDS
)

H_rep, TARGET_DENSITY_rep, PRESSURE_CONST_rep, TIME_STEP_rep = rep(H), rep(TARGET_DENSITY), rep(PRESSURE_CONST), rep(TIME_STEP)
KERNEL_COEFF_rep, DIV_KERENEL_COEFF_rep = rep(KERNEL_COEFF), rep(DIV_KERENEL_COEFF)
DAMPING_FACTOR_rep = rep(DAMPING_FACTOR)
PARAMETERS = {
    "H": H_rep, 
    "TIME_STEP": TIME_STEP_rep, 
    "PARTICLE_COUNT": N, 
    "DIMS": 2,
    "BOUND": rep(BOUNDS[0]) << 16 | rep(BOUNDS[1]),
    "TARGET_DENSITY": TARGET_DENSITY_rep,
    "PRESSURE_CONST": PRESSURE_CONST_rep,
    "KERNEL_COEFF": KERNEL_COEFF_rep,
    "DIV_KERNEL_COEFF": DIV_KERENEL_COEFF_rep,
    "DAMPING_FACTOR": DAMPING_FACTOR_rep
}

SOURCES = [
    f"{MODULE}.sv", 
    "binary16_adder.sv",
    "binary16_multi.sv",
    "binary16_sqrt.sv",
    "binary16_div.sv",
    "binary16_div_pipelined.sv",
     
    "particle_buffer.v",
    "scheduler.sv",
    
    "accumulator.sv",
    "accum_storage.sv",
    "elem_accumulator.sv",
    
    "particle_updater.sv",
    
    "pulser.sv",
    "debouncer.sv",
    
    "compute.sv",
    "calc_density.sv",
    "calc_kernel.sv",
    "calc_distance.sv",
    
    "xilinx_true_dual_port_read_first_2_clock_ram.v",
    "update_buffer.sv",
    "seven_segment_controller.sv",
    "evt_counter.sv",
    "resetter.sv",
    "lfsr_16.sv",
    "calc_spiky_kernel.sv",
]

async def generate_clock(clock_wire, fmhz=100):
    T_half = round(((1/(fmhz*1e6))/1e-9)/2,3)
    while True:
        clock_wire.value = 0
        await Timer(T_half,units="ns") # type: ignore
        clock_wire.value = 1
        await Timer(T_half,units="ns") # type: ignore

async def flash_sig(clk, sig): 
    sig.value = 1
    await RisingEdge(clk)   
    sig.value = 0    
    await RisingEdge(clk) 

async def wait(clk,cycles):
    for _ in range(cycles): await RisingEdge(clk) 

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

    clk = dut.clk_in
    dut._log.info(f"Starting {MODULE} test...")
    
    await cocotb.start(generate_clock(clk,100))
    dut.gravitational_constant.value = 0
    dut.particle_count.value = N
    dut.pressure_const.value = rep(PRESSURE_CONST)
    dut.target_density.value = rep(TARGET_DENSITY)
    await flash_sig(clk, dut.sys_rst)
    
    dut._log.info(f"Before Update Engine particles: {engine.particles[:3]}")
    dut.gravitational_constant.value = 0xCA00  
    

    if True:
        
        for _ in range(1): # frames

            # await flash_sig(clk, dut.btn[1])
            await flash_sig(clk, dut.new_frame)
            await RisingEdge(dut.frame_complete)
            dut._log.info(f"Done")
            await RisingEdge(dut.valid_particle)
            # await Timer(1, "ns")
            # await FallingEdge(dut.is_density_task)
            
            engine.update()
            forces, velocities, positions = [], [], []
            particles = []
            terms = []
            for _ in range(N):
                # pass
            
                # for _ in range(N):
                # await RisingEdge(dut.receiver_valid)
                # await Timer(1, "ns")
                # val = dut.receiver_data.value
                # val_elems = [(val & (0xFFFF << i * 16)) >> i * 16 for i in range(val.n_bits//16)]
                # dut._log.info(f"Receiver - position {hex(val)}, {half(val)}")
                # terms.append(val_elems)
                
                # # Forces 
                # await with_timeout(RisingEdge(dut.accumulator_data_valid), 10*1000, "ns")
                # force = dut.accumulator_out.value
                # force_elems = [half((force & (0xFFFF << i * 16)) >> i * 16) for i in range(force.n_bits//16)][1:]
                # forces.append(force_elems)
                
                # Velocities and positions
                await Timer(1, "ns")
                val = dut.douta.value
                position = val >> 32
                velocity = val & 0xFFFFFFFF
                # dut._log.info(f"position {hex(position)}")
                # dut._log.info(f"velocity {hex(velocity)}")
                positions.append([half((position & (0xFFFF << i * 16)) >> i * 16) for i in range(1, -1, -1)])
                velocities.append([half((velocity & (0xFFFF << i * 16)) >> i * 16) for i in range(1, -1, -1)])
                await ClockCycles(clk, 1)
                
                # velocity = dut.mp_updater.mem_out.value & 0xFFFFFFFF
                # position = dut.mp_updater.mem_out.value >> 32
                
                # velocities.append([half((velocity & (0xFFFF << i * 16)) >> i * 16) for i in range(1, -1, -1)])
                # positions.append([half((position & (0xFFFF << i * 16)) >> i * 16) for i in range(1, -1, -1)])
                # particles.append((position, velocity))                
                # await ClockCycles(clk, 1)
                # await Timer(1, "ns")
                pass

                
            await with_timeout(RisingEdge(dut.frame_complete), 10*10000, "ns")
            dut._log.info(f"Particles: {list(zip(positions, velocities))[:3]}")
            # dut._log.info(f"Particles: {[(half(p[0]), half(p[1])) for p in particles[:3]]}")
            # dut._log.info(f"Terms: {terms}")
            dut._log.info(f"Engine particles: {engine.particles[:3]}")
            # dut._log.info(f"Forces: {forces}")
            # dut._log.info(f"Engine force: {engine.pressure_forces[:3]}")
            # dut._log.info(f"Engine force: {[(hex(rep(f[1])), hex(rep(f[0]))) for f in engine.pressure_forces[:3]]}")
            # dut._log.info(f"Engine velocities: {[engine.particles[i].velocity for i in range(len(engine.particles))]}")
            # dut._log.info(f"Engine positions: {[engine.particles[i].position for i in range(len(engine.particles))]}")
            # dut._log.info(f"Engine densities: {engine.densities}")
            # dut._log.info(f"Engine pressures: {engine.pressures}")
            # dut._log.info(f"Engine pressure forces: {engine.pressure_forces}")
            dut._log.info("Frame done")
            
            # await with_timeout(RisingEdge(dut.frame_complete), 10*100, "ns") # something wrong with the updater    
        await ClockCycles(clk, 5)
        
    else:
        
        RES = (600, 600)
        PLAY_BOUNDS = (400, 400)
        # Function to draw the particle
        def draw_particle(screen, position):
            pygame.draw.circle(screen, (0, 0, 255), position, 10)  # Draw particle as a red circle

        # Convert float position to screen coordinates
        def float_to_screen_coords(binary16_pos):
            # split the dims first
            x, y = (binary16_pos & 0xFFFF0000) >> 16, binary16_pos & 0xFFFF
            x, y = half(x), half(y)
            x = (x / (2 * BOUNDS[0]) * RES[0]) + (RES[0] / 2)  # Scale and wrap around screen width
            y = (-y / (2 * BOUNDS[1]) * RES[1]) + (RES[1] / 2)  # Scale and wrap around screen height
            return (int(x), int(y))
        
        dut.gravitational_constant.value = 0xCA00   
        dut._log.info(f"BOUNDS: {hex(PARAMETERS['BOUND'])}")
        # Initialize Pygame
        pygame.init()
        screen = pygame.display.set_mode(RES)
        pygame.display.set_caption("Particle Position")
        
        running = True
        screen.fill((255, 255, 255))  
        pygame.display.flip()
        while running:
            for event in pygame.event.get():
                if event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_SPACE:
                        # read from the outside 
                        await flash_sig(clk, dut.new_frame)
                        # wait until valid_particles is high
                        await with_timeout(RisingEdge(dut.valid_particle), 10*10_000, "ns")
                        await FallingEdge(dut.clk_in)
                        # dut._log.info(f"Started Reading Particles")
                        # then read the particles off sequentially
                        screen.fill((255, 255, 255))  
                        while dut.valid_particle.value == 1:
                            # dut._log.info(f"{dut.particle_data_out.value}")                
                            screen_position = float_to_screen_coords(dut.particle_data_out.value)
                            # dut._log.info(f"Screen Position: {screen_position}")
                            # updater_pos = dut.mp_updater.particle_position.value
                            # dut._log.info(f"Updater - position {hex(updater_pos)}, {half(updater_pos)}")
                            pos = dut.particle_data_out.value
                            dut._log.info(f"position {hex(pos)}")
                            vel = dut.mp_updater.particle_velocity.value
                            dut._log.info(f"velocity {hex(vel)}")
                            draw_particle(screen, screen_position)
                            await FallingEdge(dut.clk_in)
                        await with_timeout(RisingEdge(dut.frame_complete), 10*1000, "ns")
                        pygame.display.flip()   
                    elif event.key == pygame.K_ESCAPE:
                        running = False
                if event.type == pygame.QUIT:
                    running = False

        pygame.quit()
        await wait(clk, 2)

    
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
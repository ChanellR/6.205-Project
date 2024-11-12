import sys
import os
from typing import Callable, List, Tuple
import copy
from functools import partial
import numpy as np
import pygame
import sys
from dataclasses import dataclass
from math import pi
from multiprocessing import Pool
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor


def curry(f):
    def curried_function(*args):
        if len(args) == f.__code__.co_argcount:
            return f(*args)
        return lambda *more_args: curried_function(*(args + more_args))
    return curried_function


@dataclass
class Particle:
    def __init__(self, position, velocity):
        self.position = position
        self.velocity = velocity
        
    def __copy__(self):
        return Particle(self.position, self.velocity)
    
    
def generate_random_particles(num_particles, bounds):
    particles = []
    for _ in range(num_particles):
        position = np.array([
            np.random.uniform(0, bounds[0]),
            np.random.uniform(0, bounds[1])
        ], dtype='float64')
        velocity = np.array([0, 0], dtype='float64')
        particles.append(Particle(position, velocity))
    return particles

def generate_grid_particles(rows, cols, spacing, bounds):
    particles = []
    for i in range(rows):
        for j in range(cols):
            position = np.array([
                i * spacing % bounds[0],
                j * spacing % bounds[1]
            ], dtype='float64')
            velocity = np.array([0, 0], dtype='float64')
            particles.append(Particle(position, velocity))
    return particles

def generate_grid_particles_in_rectangle(num_particles, rect):
    particles = []
    x_min, y_min, width, height = rect
    rows = int(np.sqrt(num_particles * height / width))
    cols = num_particles // rows
    x_spacing = width / cols
    y_spacing = height / rows
    for i in range(rows):
        for j in range(cols):
            position = np.array([
                x_min + j * x_spacing,
                y_min + i * y_spacing
            ], dtype='float64')
            velocity = np.array([0, 0], dtype='float64')
            particles.append(Particle(position, velocity))
    return particles


def random_dir():
    v = np.array([np.random.uniform(-1, 1), np.random.uniform(-1, 1)], dtype='float64')
    return v / np.linalg.norm(v)


class SPH_Engine:
    def __init__(self, 
                particles: List[Particle], 
                mass: float,
                time_step: float, 
                h: float, 
                kernel, 
                kernel_gradient, 
                target_density: float, 
                pressure_coeff: float, 
                gravitational_constant: float,
                bounds: Tuple[float, float], 
                collision_damping: float):
        
        self.particles = list(copy.copy(p) for p in particles)
        N = len(self.particles)
        
        self.predicted_positions = [np.array([0, 0], dtype='float64') for _ in range(N)]
        self.densities = {}
        self.pressures = {}
        self.pressure_forces = {}
        
        # time step and smoothing length
        self.time_step = time_step
        self.h = h
        
        # pressure, and density kernel
        self.kernel = kernel
        self.kernel_gradient = kernel_gradient
        
        # simulation constants
        self.target_density = target_density
        self.pressure_coeff = pressure_coeff
        self.mass = mass
        
        # gravity force
        self.gravity_force = np.array([0, gravitational_constant], dtype='float64')
        self.collision_damping = collision_damping
        
        # bounds
        self.bounds = bounds
        self.grid = {}

    def calculate_density(self, i):
        density = 0
        for j in self.get_neighboring_particles(i):
        # for j in range(len(self.particles)):
            distance = np.linalg.norm(self.predicted_positions[j] - self.predicted_positions[i])
            # distance = np.linalg.norm(self.particles[j].position - self.particles[i].position)
            density += self.mass * self.kernel(distance, self.h)
                
        return density

    def pressure_force(self, i):
        p = self.particles[i]
        pressure_force = np.zeros(2)
        for j, q in enumerate(self.particles):
            if i == j:
                continue
            distance = np.linalg.norm(q.position - p.position)
            dir = (q.position - p.position) / distance if distance > 0 else random_dir()
            f_p = -self.mass * (self.pressures[i] + self.pressures[j]) / (2 * self.densities[j]) * self.kernel_gradient(distance, self.h) * dir
            pressure_force += f_p
            
        return pressure_force

    def update_particle(self, i):
        
        p = self.particles[i]
        accel = (self.pressure_forces[i] + self.gravity_force) / self.densities[i]
        p.velocity += self.time_step * accel
        next_position = p.position + self.time_step * p.velocity

        if next_position[0] < 0 or next_position[0] > self.bounds[0]:
            p.velocity[0] = -p.velocity[0] * self.collision_damping
        if next_position[1] < 0 or next_position[1] > self.bounds[1]:
            p.velocity[1] = -p.velocity[1] * self.collision_damping

        p.position += self.time_step * p.velocity

        if p.position[0] < 0 or p.position[0] > self.bounds[0] or p.position[1] < 0 or p.position[1] > self.bounds[1]:
            p.position = np.clip(p.position, 0, self.bounds)
            p.velocity = np.array([0, 0], dtype='float64')
            
        return p
    
    def get_neighboring_particles(self, i):
        grid_x = int(self.predicted_positions[i][0] // self.h)
        grid_y = int(self.predicted_positions[i][1] // self.h)
        for dx in [-1, 0, 1]:
            for dy in [-1, 0, 1]:
                neighbor_cell = (grid_x + dx, grid_y + dy)
                if neighbor_cell in self.grid:
                    yield from self.grid[neighbor_cell]    

    def update(self):
        
        # calculate densities and pressures
        for i, p in enumerate(self.particles):
            self.predicted_positions[i] = (p.position + (self.time_step * p.velocity))
            
        # Partition the bounds into squares of width h
        self.grid = {}
        for i in range(len(self.particles)):
            grid_x = int(self.predicted_positions[i][0] // self.h)
            grid_y = int(self.predicted_positions[i][1] // self.h)
            if (grid_x, grid_y) not in self.grid:
                self.grid[(grid_x, grid_y)] = []
            self.grid[(grid_x, grid_y)].append(i)

        N = len(self.particles) 
        if N <= 100:
            
            for i in range(len(self.particles)):
                density = self.calculate_density(i)
                self.densities[i] = density
                self.pressures[i] = self.pressure_coeff * (density - self.target_density)

            # Then, calculate pressure forces and update particle positions
            for i in range(len(self.particles)):
                self.pressure_forces[i] = self.pressure_force(i)
                self.particles[i] = self.update_particle(i)
                
        else:          
            
            workers = os.cpu_count()
            workers = workers if workers is not None else 4
            
            # # overhead makes this too slow
            with ProcessPoolExecutor(max_workers=workers) as executor:
                
                # First, calculate densities and pressures
                for i, density in enumerate(executor.map(self.calculate_density, range(len(self.particles)), chunksize=N//workers)):
                    self.densities[i] = density
                    self.pressures[i] = self.pressure_coeff * (density - self.target_density)

                # Then, calculate pressure forces
                for i, pressure_force in enumerate(executor.map(self.pressure_force, range(len(self.particles)), chunksize=N//workers)):
                    self.pressure_forces[i] = pressure_force
                    self.particles[i] = self.update_particle(i)
                            
                
    def get_particles(self):
        return list(copy.copy(p) for p in self.particles)

    def add_particle(self, particle):
        self.particles.append(particle)

    def remove_particle(self, particle):
        self.particles.remove(particle)


class SPH_Visualizer:
    
    def __init__(self, engine: SPH_Engine, width: int = 800, height: int = 600, particle_radius: int = 5):
        
        self.engine = engine
        self.width = width
        self.height = height
        self.particle_radius = particle_radius
        
        pygame.init()
        self.screen = pygame.display.set_mode((self.width, self.height))
        pygame.display.set_caption('SPH Engine Visualization')
        self.clock = pygame.time.Clock()
        
        # Slider parameters
        self.slider_height = 20
        self.slider_width = 200
        self.sliders = {
            'time_step': {'value': self.engine.time_step, 'min': 0.01, 'max': 0.5, 'pos': (10, 10)},
            'h': {'value': self.engine.h, 'min': 0.1, 'max': 8.0, 'pos': (10, 40)},
            'target_density': {'value': self.engine.target_density, 'min': 0.01, 'max': 20.0, 'pos': (10, 70)},
            'pressure_coeff': {'value': self.engine.pressure_coeff, 'min': 0.01, 'max': 100, 'pos': (10, 100)},
            'gravitational_constant': {'value': self.engine.gravity_force[1], 'min': -40, 'max': 0, 'pos': (10, 130)},
            'collision_damping': {'value': self.engine.collision_damping, 'min': 0, 'max': 1, 'pos': (10, 160)}
        }

    def draw_slider(self, name, slider):
        pygame.draw.rect(self.screen, (200, 200, 200), (*slider['pos'], self.slider_width, self.slider_height))
        handle_pos = slider['pos'][0] + (slider['value'] - slider['min']) / (slider['max'] - slider['min']) * self.slider_width
        pygame.draw.rect(self.screen, (100, 100, 100), (handle_pos - 5, slider['pos'][1], 10, self.slider_height))
        font = pygame.font.Font(None, 24)
        text = font.render(f"{name}: {slider['value']:.2f}", True, (0, 0, 0))
        self.screen.blit(text, (slider['pos'][0] + self.slider_width + 10, slider['pos'][1]))

    def update_slider(self, pos):
        for name, slider in self.sliders.items():
            if slider['pos'][0] <= pos[0] <= slider['pos'][0] + self.slider_width and slider['pos'][1] <= pos[1] <= slider['pos'][1] + self.slider_height:
                slider['value'] = slider['min'] + (pos[0] - slider['pos'][0]) / self.slider_width * (slider['max'] - slider['min'])
                setattr(self.engine, name, slider['value'])
                if name == 'gravitational_constant':
                    self.engine.gravity_force[1] = slider['value']

    def draw_particles(self):
        self.screen.fill((255, 255, 255))
        # draw bounds
        # pygame.draw.rect(self.screen, (0, 0, 0), (self.width / 2 - self.engine.bounds[0], self.height / 2 - self.engine.bounds[1], self.engine.bounds[0] * 2, self.engine.bounds[1] * 2), 1)
        height = 380
        work_field = (20, 200, int(height * (self.engine.bounds[0]/self.engine.bounds[1])), height)
        pygame.draw.rect(self.screen, (0, 0, 0), work_field, 1)
        
        # draw particles
        for particle in self.engine.get_particles():
            x, y = particle.position
            w, l = self.engine.bounds
            # center = (int(particle.position[0]) + int(self.width/2), -int(particle.position[1]) + int(self.height/2))
            center = (work_field[0] + int(x/w * work_field[2]), work_field[1] + height - int(y/l * work_field[3]))
            pygame.draw.circle(self.screen, (0, 0, 255), center, self.particle_radius)
        # draw sliders
        for name, slider in self.sliders.items():
            self.draw_slider(name, slider)
        pygame.display.flip()

    def reset(self):
        # particles = generate_grid_particles(10, 10, 0.75, self.engine.bounds)
        # particles = generate_random_particles(400, self.engine.bounds)
        # particles = generate_grid_particles_in_rectangle(400, (7, 3, 3, 3))
        self.engine.particles = generate_random_particles(len(self.engine.particles), self.engine.bounds)
        
    def run(self):
        running = True
        play = False
        frame = 0
        while running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                if event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_r:
                        self.reset()
                    if event.key == pygame.K_RETURN:
                        play = not play
                    if not play and event.key == pygame.K_SPACE:
                        print("Frame:", frame)
                        self.engine.update()
                        frame += 1
                if event.type == pygame.MOUSEBUTTONDOWN:
                    self.update_slider(event.pos)
            if play:
                self.engine.update()
                frame += 1
            self.draw_particles()
            
            # Display FPS
            fps = self.clock.get_fps()
            font = pygame.font.Font(None, 24)
            fps_text = font.render(f"FPS: {fps:.2f}", True, (0, 0, 0))
            self.screen.blit(fps_text, (self.width - 100, 10))
            
            pygame.display.flip()
            self.clock.tick(60)
        pygame.quit()
        sys.exit()

 
def smoothing_kernel(r, h):
    if r >= h:
        return 0
    volume = pi * (h**4) / 6
    return ((r - h)**2) / volume

def smoothing_kernel_gradient(r, h):
    if r >= h:
        return 0
    scale = 12 / (pi * h**4)
    return scale * (h - r)

if __name__ == "__main__":
    # Example usage
    bounds = (16, 9)
    
    # particles = generate_grid_particles(10, 10, 0.75, bounds)
    # particles = generate_random_particles(400, bounds)
    particles = generate_grid_particles_in_rectangle(400, (7, 3, 3, 3))
    
    engine = SPH_Engine(particles, 
                        mass=1.0, 
                        time_step=1/60, 
                        h=1.2, 
                        # kernel=lambda r, h: max(0, h - r), 
                        # kernel_gradient=lambda r, h: -1 if r < h else 0,
                        kernel=smoothing_kernel,
                        kernel_gradient=smoothing_kernel_gradient,
                        target_density=2.75, 
                        pressure_coeff=0.5, 
                        gravitational_constant=0,
                        collision_damping=0.95, 
                        bounds=bounds)

    visualizer = SPH_Visualizer(engine, particle_radius=5)
    visualizer.run()

from typing import Callable, List, Tuple
import copy
from functools import partial
import numpy as np
import pygame
import sys
from dataclasses import dataclass


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
                bounds: Tuple[float, float]):
        
        self.particles = list(copy.copy(p) for p in particles)
        
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
        self.gravity_force = np.array([0, gravitational_constant])
        
        # bounds
        self.bounds = bounds

    def update(self):
        
        densities = {}
        pressures = {}
        for i, p in enumerate(self.particles):
            density = 0
            for q in self.particles:
                density += self.mass * self.kernel(np.linalg.norm(p.position - q.position), self.h)
            densities[i] = density
            pressures[i] = self.pressure_coeff * (density - self.target_density)
            
        pressure_forces = {}
        for i, p in enumerate(self.particles):
            pressure_force = np.zeros(2)
            for j, q in enumerate(self.particles):
                if i == j:
                    continue
                distance = np.linalg.norm(p.position - q.position)
                if distance > 0:
                    unit_vector = (p.position - q.position) / distance
                    pressure_force += -self.mass * (pressures[i] + pressures[j]) / (2 * densities[j]) * self.kernel_gradient(distance, self.h) * unit_vector
            print(f"particle {i} pressure force: {pressure_force}")
            pressure_forces[i] = pressure_force
            
        for i, p in enumerate(self.particles):
            p.velocity += self.time_step * (pressure_forces[i] + self.gravity_force) / self.mass
            next_position = p.position + self.time_step * p.velocity
            
            if next_position[0] < -self.bounds[0] or next_position[0] > self.bounds[0]:
                p.velocity[0] = -p.velocity[0]
            if next_position[1] < -self.bounds[1] or next_position[1] > self.bounds[1]:
                p.velocity[1] = -p.velocity[1]
                
            p.position += self.time_step * p.velocity 
            
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
            'time_step': {'value': self.engine.time_step, 'min': 0.001, 'max': 0.1, 'pos': (10, 10)},
            'h': {'value': self.engine.h, 'min': 1.0, 'max': 20.0, 'pos': (10, 40)},
            'target_density': {'value': self.engine.target_density, 'min': 0.1, 'max': 10.0, 'pos': (10, 70)},
            'pressure_coeff': {'value': self.engine.pressure_coeff, 'min': 0.1, 'max': 10.0, 'pos': (10, 100)},
            'gravitational_constant': {'value': self.engine.gravity_force[1], 'min': -500, 'max': 0, 'pos': (10, 130)}
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
        pygame.draw.rect(self.screen, (0, 0, 0), (self.width / 2 - self.engine.bounds[0], self.height / 2 - self.engine.bounds[1], self.engine.bounds[0] * 2, self.engine.bounds[1] * 2), 1)
        # draw particles
        for particle in self.engine.get_particles():
            center = (int(particle.position[0]) + int(self.width/2), -int(particle.position[1]) + int(self.height/2))
            pygame.draw.circle(self.screen, (0, 0, 255), center, self.particle_radius)
        # draw sliders
        for name, slider in self.sliders.items():
            self.draw_slider(name, slider)
        pygame.display.flip()

    def run(self):
        running = True
        while running:
            pause = False
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                if event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_SPACE:
                        pause = True
                if event.type == pygame.MOUSEBUTTONDOWN:
                    self.update_slider(event.pos)
            if not pause:
                self.engine.update()
                self.draw_particles()
            self.clock.tick(60)
        pygame.quit()
        sys.exit()


# Example usage:
particles = [Particle(np.array([0, 0], dtype='float64'), np.array([0, 0], dtype='float64'))]

N = 2  # Number of particles per row/column
spacing = 20  # Spacing between particles
particles = []
for i in range(N):
    for j in range(N):
        position = np.array([i * spacing - (N * spacing) / 2, j * spacing - (N * spacing) / 2], dtype='float64')
        velocity = np.array([0, 0], dtype='float64')
        particles.append(Particle(position, velocity))

engine = SPH_Engine(particles, 
                    mass=1.0, 
                    time_step=0.01, 
                    h=10.0, 
                    kernel=lambda r, h: max(0, h - r), 
                    kernel_gradient=lambda r, h: -1 if r < h else 0, 
                    target_density=1.0, 
                    pressure_coeff=1.0, 
                    gravitational_constant=-100, 
                    bounds=(100, 100))

visualizer = SPH_Visualizer(engine)
visualizer.run()
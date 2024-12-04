import numpy as np
import matplotlib.pyplot as plt
from OpenGL.GL import *
from OpenGL.GLU import *

def plot_xy_points(points):
    """
    Plots the x and y values of 3D points.

    Parameters:
    - points: numpy array of shape (n, 3), where each row is a 3D point (x, y, z).
    """
    # Extract x and y coordinates from the points
    x = points[:, 0]
    y = points[:, 1]

    # Create a scatter plot
    plt.scatter(x, y, c='blue', marker='o', label='Points')

    # Add labels and title
    plt.xlabel('X')
    plt.ylabel('Y')
    plt.title('Scatter Plot of X and Y values of 3D Points')

    plt.gca().set_aspect('equal', adjustable='box')

    # Display the plot
    plt.legend()
    plt.grid(True)
    plt.show()

# Function to generate the cube vertices
def generate_cube_points(side_length=2, center=np.array([0.0, 0.0, 0.0])):
    # Half side length
    half_side = side_length / 2

    # Define the 8 vertices of the cube (using combinations of ±half_side)
    cube_vertices = np.array([
        [ x,  y,  z]
        for x in [-half_side, half_side]
        for y in [-half_side, half_side]
        for z in [-half_side, half_side]
    ])
    
    # Apply translation to center the cube at the given center
    cube_vertices += center

    return cube_vertices

def apply_mvp_to_cube(cube_vertices, mvp_matrix):
    # Convert the cube vertices to homogeneous coordinates (add a 1 in the 4th column)
    homogeneous_cube_vertices = np.hstack([cube_vertices, np.ones((cube_vertices.shape[0], 1))])

    # Apply the MVP matrix to each vertex
    transformed_vertices = homogeneous_cube_vertices @ mvp_matrix.T  # MVP * Vertex

    # Return the transformed vertices (we discard the homogeneous coordinate for 3D points)
    return transformed_vertices[:, :-1]

import numpy as np

def create_model_matrix(scale=(1, 1, 1), rotation=(0, 0, 0), translation=(0, 0, 0)):
    """
    Create a model matrix using scale, rotation, and translation.
    
    Args:
    - scale: Tuple (sx, sy, sz) for scaling
    - rotation: Tuple (rx, ry, rz) for rotation (in degrees)
    - translation: Tuple (tx, ty, tz) for translation
    
    Returns:
    - 4x4 model matrix
    """
    # Create scaling matrix
    scale_matrix = np.array([
        [scale[0], 0, 0, 0],
        [0, scale[1], 0, 0],
        [0, 0, scale[2], 0],
        [0, 0, 0, 1]
    ])
    
    # Create rotation matrices for each axis (assuming rotation in degrees)
    rad = np.radians(rotation)
    cosx, sinx = np.cos(rad[0]), np.sin(rad[0])
    cosy, siny = np.cos(rad[1]), np.sin(rad[1])
    cosz, sinz = np.cos(rad[2]), np.sin(rad[2])
    
    # Rotation matrix for X axis
    rot_x = np.array([
        [1, 0, 0, 0],
        [0, cosx, -sinx, 0],
        [0, sinx, cosx, 0],
        [0, 0, 0, 1]
    ])
    
    # Rotation matrix for Y axis
    rot_y = np.array([
        [cosy, 0, siny, 0],
        [0, 1, 0, 0],
        [-siny, 0, cosy, 0],
        [0, 0, 0, 1]
    ])
    
    # Rotation matrix for Z axis
    rot_z = np.array([
        [cosz, -sinz, 0, 0],
        [sinz, cosz, 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1]
    ])
    
    # Combine the rotation matrices
    rotation_matrix = np.dot(np.dot(rot_z, rot_y), rot_x)
    
    # Create translation matrix
    translation_matrix = np.array([
        [1, 0, 0, translation[0]],
        [0, 1, 0, translation[1]],
        [0, 0, 1, translation[2]],
        [0, 0, 0, 1]
    ])
    
    # Combine all transformations: scale -> rotate -> translate
    model_matrix = np.dot(np.dot(translation_matrix, rotation_matrix), scale_matrix)
    
    return model_matrix

def create_view_matrix(eye, center, up):
    """
    Create a view matrix using the "LookAt" approach.
    
    Args:
    - eye: Position of the camera (e.g., (x, y, z))
    - center: Point the camera is looking at (e.g., (x, y, z))
    - up: Up direction of the camera (e.g., (0, 1, 0))
    
    Returns:
    - 4x4 view matrix
    """
    f = np.array(center) - np.array(eye)
    f = f / np.linalg.norm(f)
    
    r = np.cross(up, f)
    r = r / np.linalg.norm(r)
    
    u = np.cross(f, r)
    u = u / np.linalg.norm(u)
    
    # Create view matrix (right, up, forward, position)
    view_matrix = np.array([
        [r[0], u[0], -f[0], 0],
        [r[1], u[1], -f[1], 0],
        [r[2], u[2], -f[2], 0],
        [-np.dot(r, eye), -np.dot(u, eye), np.dot(f, eye), 1]
    ])
    
    return view_matrix

def create_projection_matrix(fov, aspect, near, far):
    """
    Create a perspective projection matrix.
    
    Args:
    - fov: Field of view (in degrees)
    - aspect: Aspect ratio (width / height)
    - near: Near clipping plane
    - far: Far clipping plane
    
    Returns:
    - 4x4 projection matrix
    """
    fov_rad = np.radians(fov)
    f = 1 / np.tan(fov_rad / 2)
    
    # Perspective projection matrix
    projection_matrix = np.array([
        [f / aspect, 0, 0, 0],
        [0, f, 0, 0],
        [0, 0, (far + near) / (near - far), (2 * far * near) / (near - far)],
        [0, 0, -1, 0]
    ])
    
    return projection_matrix

def create_mvp_matrix(model_matrix, view_matrix, projection_matrix):
    """
    Combine the Model, View, and Projection matrices into the MVP matrix.
    
    Args:
    - model_matrix: 4x4 model matrix
    - view_matrix: 4x4 view matrix
    - projection_matrix: 4x4 projection matrix
    
    Returns:
    - 4x4 MVP matrix
    """
    # The correct order is P * V * M (Projection * View * Model)
    mvp_matrix = np.dot(np.dot(projection_matrix, view_matrix), model_matrix)
    return mvp_matrix

# Example usage
scale = (1, 1, 1)
rotation = (0, 0, 0)  # Rotate 45 degrees around each axis
translation = (0, 0, 0)
model_matrix = create_model_matrix(scale, rotation, translation)

eye = (0, 0, 5)
center = (0, 0, 0)
up = (0, 1, 0)
view_matrix = create_view_matrix(eye, center, up)

fov = 60
aspect = 1.77  # 16:9 aspect ratio
near = 0.1
far = 100.0
projection_matrix = create_projection_matrix(fov, aspect, near, far)

print("Model Matrix:\n", model_matrix)
print("View Matrix:\n", view_matrix)
print("Projection Matrix:\n", projection_matrix)

# Calculate MVP matrix
mvp_matrix = create_mvp_matrix(model_matrix, view_matrix, projection_matrix)
print("MVP Matrix:\n", mvp_matrix)

t = apply_mvp_to_cube(generate_cube_points(), mvp_matrix)
plot_xy_points(t)
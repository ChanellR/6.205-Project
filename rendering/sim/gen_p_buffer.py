import numpy as np

def float16_to_bin(value):
    """Convert a float16 value to its binary string representation."""
    # Convert to np.float16 and get the bit representation as an integer
    return np.binary_repr(np.float16(value).view(np.int16), width=16)

def bin_to_hex(bin_str):
    """Convert a binary string to its hexadecimal representation."""
    # Convert the binary string to an integer, then to a hexadecimal string
    return hex(int(bin_str, 2))[2:].zfill(4)  # zfill to ensure 4 hex digits

def generate_random_positions():
    for _ in range(200):
        # Generate random x, y, z coordinates in the range (-6, 6)
        x = np.random.uniform(-6, 6)
        y = np.random.uniform(-6, 6)
        z = np.random.uniform(-6, 6)

        # Convert the floating-point values to 16-bit binary format
        x_bin = float16_to_bin(x)
        y_bin = float16_to_bin(y)
        z_bin = float16_to_bin(z)

        # Convert the binary strings to hexadecimal
        x_hex = bin_to_hex(x_bin)
        y_hex = bin_to_hex(y_bin)
        z_hex = bin_to_hex(z_bin)

        # Concatenate the hexadecimal strings
        concatenated_position = x_hex + y_hex + z_hex

        # Prepend '47'b' to the front and add a comma at the end
        concatenated_position = "48'h" + concatenated_position + ","
        
        # Print the result
        print(concatenated_position)

# Call the function to generate and print 200 random positions
generate_random_positions()
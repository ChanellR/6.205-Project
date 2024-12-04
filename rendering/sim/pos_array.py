import struct

# Function to convert float to 16-bit half-precision binary representation
def float_to_half_precision_bin(value):
    # Use struct to convert float to 16-bit half precision (FP16)
    return format(struct.unpack('H', struct.pack('e', value))[0], '016b')

# Generate the 64 numbers between -5 and 5
numbers = [-5 + (10 * i) / 63 for i in range(64)]

# Convert each number to its binary representation (16-bit)
binary_numbers = [float_to_half_precision_bin(num) for num in numbers]

sv_array_string = "{"
# Print the binary numbers
for num, bin_num in zip(numbers, binary_numbers):
    print(f"{num}: {bin_num}")

    for bin_num in binary_numbers:
      sv_array_string += f"  16'b{bin_num},\n"

# Close the array definition
sv_array_string += "};\n"
print(sv_array_string)

# Write the SystemVerilog array format to a file
with open("./float_pos_values.sv", "w") as file:
    file.write(sv_array_string)
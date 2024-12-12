import sys

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
    
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python convert.py <value1> <value2> ... <valueN>")
        sys.exit(1)

    for hex_value in sys.argv[1:]:
        try:
            val = eval(f"0x{hex_value}")
        except ValueError:
            print(f"Please provide a valid number for {hex_value}.")
            continue

        result = half(val)
        print(f"(0x{hex_value}) == {result}")
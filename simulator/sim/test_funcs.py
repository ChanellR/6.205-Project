import numpy as np

def rep(val):
    return eval(f"0b{float32_to_binary16(val).view(np.uint16):016b}")

def float32_to_binary16(val):
    """Convert a 32-bit floating point number to a binary16 value."""
    return np.float16(val)

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
    
def float_to_binary16_int_rep(val):
    return eval(f"0b{float32_to_binary16(val).view(np.uint16):016b}")

#!/usr/bin/env python3
import sys
import os

def convert_metallib_to_header(metallib_path, header_path, target_name):
    """Convert a metallib binary file to a C++ header with embedded data."""
    
    # Read the metallib binary data
    with open(metallib_path, 'rb') as f:
        data = f.read()
    
    # Generate the header content
    header_content = """// Auto-generated file containing embedded Metal library
#pragma once
#include <cstddef>

namespace """ + target_name + """_metal {
    static const unsigned char metallib_data[] = {
"""
    
    # Convert binary data to C array format
    bytes_per_line = 16
    for i in range(0, len(data), bytes_per_line):
        chunk = data[i:i + bytes_per_line]
        hex_values = ', '.join('0x{:02x}'.format(b) for b in chunk)
        header_content += "        " + hex_values + ","
        if i + bytes_per_line < len(data):
            header_content += "\n"
    
    header_content += """
    };
    static const size_t metallib_data_len = """ + str(len(data)) + """;
} // namespace """ + target_name + """_metal
"""
    
    # Write the header file
    dir_path = os.path.dirname(header_path)
    if dir_path:
        os.makedirs(dir_path, exist_ok=True)
    with open(header_path, 'w') as f:
        f.write(header_content)
    
    print("Generated {} ({} bytes)".format(header_path, len(data)))

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: metallib_to_header.py <metallib_path> <header_path> <target_name>")
        sys.exit(1)
    
    metallib_path = sys.argv[1]
    header_path = sys.argv[2]
    target_name = sys.argv[3]
    
    convert_metallib_to_header(metallib_path, header_path, target_name)
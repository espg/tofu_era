#!/usr/bin/env python3
"""
Simple YAML to JSON converter for the import script
Falls back to basic parsing if PyYAML is not available
"""

import sys
import json

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

def basic_yaml_parser(yaml_str):
    """
    Basic YAML parser for simple AWS CLI output
    This is a fallback when PyYAML is not available
    """
    result = {}
    current_obj = result
    stack = [result]
    indent_stack = [0]

    for line in yaml_str.split('\n'):
        if not line.strip() or line.strip().startswith('#'):
            continue

        # Calculate indentation
        indent = len(line) - len(line.lstrip())

        # Handle dedentation
        while indent_stack and indent < indent_stack[-1]:
            indent_stack.pop()
            stack.pop()
            if stack:
                current_obj = stack[-1]

        line = line.strip()

        if ':' in line:
            key, value = line.split(':', 1)
            key = key.strip()
            value = value.strip()

            if value:
                # Simple key-value pair
                # Try to parse as JSON types
                if value.startswith("'") and value.endswith("'"):
                    value = value[1:-1]
                elif value.startswith('"') and value.endswith('"'):
                    value = value[1:-1]
                elif value.lower() == 'true':
                    value = True
                elif value.lower() == 'false':
                    value = False
                elif value.lower() == 'null' or value.lower() == '~':
                    value = None
                else:
                    try:
                        # Try to parse as number
                        if '.' in value:
                            value = float(value)
                        else:
                            value = int(value)
                    except ValueError:
                        pass  # Keep as string

                current_obj[key] = value
            else:
                # Start of nested object
                new_obj = {}
                current_obj[key] = new_obj
                stack.append(new_obj)
                indent_stack.append(indent + 2)  # Assume 2-space indent
                current_obj = new_obj
        elif line.startswith('- '):
            # List item
            item = line[2:].strip()
            if isinstance(current_obj, dict):
                # Convert to list
                last_key = list(current_obj.keys())[-1]
                current_obj[last_key] = [item]
            elif isinstance(current_obj, list):
                current_obj.append(item)

    return result

def main():
    if len(sys.argv) != 3:
        print("Usage: yaml-to-json.py <input_file> <output_file>", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    try:
        with open(input_file, 'r') as f:
            yaml_content = f.read()

        if HAS_YAML:
            # Use PyYAML if available
            data = yaml.safe_load(yaml_content)
        else:
            # Fallback to basic parser
            data = basic_yaml_parser(yaml_content)

        with open(output_file, 'w') as f:
            json.dump(data, f, indent=2)

        print(f"Successfully converted {input_file} to {output_file}")

    except Exception as e:
        print(f"Error converting YAML to JSON: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
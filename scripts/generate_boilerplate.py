#!/usr/bin/env python3
"""Reads StateExpr.swift cases and generates boilerplate for all switch sites."""

import re, sys

def parse_cases(path):
    with open(path) as f: content = f.read()
    # Match: case name(params)
    cases = re.findall(r'case (\w+)\((.*?)\)', content)
    parsed = []
    for name, params in cases:
        params = [p.strip() for p in params.split(',') if p.strip()]
        parsed.append((name, params))
    return parsed

def generate_description(cases):
    lines = []
    for name, params in cases:
        if not params:
            lines.append(f'        case .{name}: return "{name}"')
        elif len(params) == 1:
            lines.append(f'        case .{name}(let a): return "{name}(\\\\(a))"')
        elif len(params) == 2:
            lines.append(f'        case .{name}(let a, let b): return "{name}(\\\\(a), \\\\(b))"')
    return '\n'.join(lines)

def generate_evaluator(cases):
    lines = []
    for name, params in cases:
        args = ', '.join(f'try evaluateRecursively(a{i}, in: state)' for i in range(len(params)))
        if not params:
            lines.append(f'        case .{name}: return .bool(true) // TODO')
        elif len(params) == 1:
            lines.append(f'        case .{name}(let a0): return {args}')
        elif len(params) == 2:
            lines.append(f'        case .{name}(let a0, let a1): return {args}')
    return '\n'.join(lines)

def generate_substitute_variable(cases):
    lines = []
    for name, params in cases:
        args = ', '.join(f'sub(a{i})' for i in range(len(params)))
        if not params:
            lines.append(f'        case .{name}: return .{name}')
        elif len(params) == 1:
            lines.append(f'        case .{name}(let a0): return .{name}({args})')
        elif len(params) == 2:
            lines.append(f'        case .{name}(let a0, let a1): return .{name}({args})')
    return '\n'.join(lines)

if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'Sources/SwiftTLA/StateExpr.swift'
    cases = parse_cases(path)
    print(f"// {len(cases)} cases found")
    print("\n// --- Descriptions ---")
    print(generate_description(cases))
    print("\n// --- Evaluator ---")
    print(generate_evaluator(cases))
    print("\n// --- substituteVariable ---")
    print(generate_substitute_variable(cases))

#!/usr/bin/env python3
"""
tools/generate_code.py -> Forwarder to tools/ios/generate_code.py
"""
import pathlib
import runpy

SCRIPT = pathlib.Path(__file__).resolve().parent / "ios" / "generate_code.py"
runpy.run_path(str(SCRIPT), run_name="__main__")


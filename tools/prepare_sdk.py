#!/usr/bin/env python3
"""
tools/prepare_sdk.py - Root wrapper for tools/ios/prepare_sdk.py
"""
import os
import pathlib
import subprocess
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
TARGET_SCRIPT = SCRIPT_DIR / "ios" / "prepare_sdk.py"

if __name__ == "__main__":
    if TARGET_SCRIPT.is_file():
        cmd = [sys.executable, str(TARGET_SCRIPT)] + sys.argv[1:]
        sys.exit(subprocess.call(cmd))
    else:
        sys.exit(f"[ERROR] {TARGET_SCRIPT} not found")


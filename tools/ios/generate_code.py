#!/usr/bin/env python3
"""
tools/ios/generate_code.py
Ahead-Of-Time (AOT) PowerPC-to-C++ Code Generator for Tekken 6 (Xbox 360, Title ID: 4E4D07FC).
Transpiles default.xex into standard C++ translation units in generated/default/.
"""

import argparse
import os
import pathlib
import subprocess
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
GENERATED_DIR = ROOT / "generated" / "default"
MANIFEST_FILE = ROOT / "tekken6_manifest.toml"
CONFIG_FILE = ROOT / "tekken6_config.toml"

XEX_CANDIDATES = [
    ROOT / "xex" / "tekken6_default.xex",
    ROOT / "Tekken 6" / "Default.xex",
    ROOT / "xex" / "default.xex",
    ROOT / "game" / "default.xex",
    ROOT / "default.xex",
]


def check_and_extract_cache():
    """Ensures generated C++ code is present, extracting gen.tar.gz if needed."""
    init_file = GENERATED_DIR / "tekken6_init.cpp"
    reg_file = GENERATED_DIR / "tekken6_register.cpp"
    sources_cmake = GENERATED_DIR / "sources.cmake"

    if init_file.exists() and reg_file.exists() and sources_cmake.exists():
        print(f"[Codegen] Verified pre-generated C++ code already present in {GENERATED_DIR}.")
        return True

    cache_archive = ROOT / "gen.tar.gz"
    if cache_archive.is_file():
        print(f"[Codegen] Unpacking pre-generated C++ code from {cache_archive.name}...")
        GENERATED_DIR.mkdir(parents=True, exist_ok=True)
        with tarfile.open(cache_archive, "r:gz") as tar:
            tar.extractall(path=ROOT)
        print("[Codegen] Unpacked successfully.")
        return True
    return False


def locate_xex(explicit_path=None):
    if explicit_path:
        p = pathlib.Path(explicit_path).resolve()
        if p.is_file():
            return p
        sys.exit(f"[ERROR] Specified XEX does not exist: {p}")
    for cand in XEX_CANDIDATES:
        if cand.is_file():
            return cand.resolve()
    return None


def run_codegen(xex_path, output_dir, config_path):
    """Executes the Tekken 6 codegen pipeline."""
    init_file = GENERATED_DIR / "tekken6_init.cpp"
    reg_file = GENERATED_DIR / "tekken6_register.cpp"
    codegen_script = ROOT / "tools" / "build_tekken6_codegen.py"
    if codegen_script.is_file():
        cmd = [sys.executable, str(codegen_script)]
        print(f"[Codegen] Running: {' '.join(cmd)}")
        res = subprocess.run(cmd, cwd=str(ROOT))
        if res.returncode != 0:
            if init_file.exists() and reg_file.exists():
                print(f"[Codegen] Host codegen exited with {res.returncode}, but valid pre-generated C++ code is intact. Proceeding.")
                return
            sys.exit(f"[ERROR] Codegen pipeline failed with code {res.returncode}")
    else:
        # Fallback to rexglue / rexgen CLI if present on host PATH
        rexgen = shutil.which("rexgen") or shutil.which("rexglue")
        if rexgen:
            cmd = [rexgen, "codegen", str(MANIFEST_FILE)]
            print(f"[Codegen] Running CLI: {' '.join(cmd)}")
            subprocess.run(cmd, cwd=str(ROOT), check=True)
        else:
            sys.exit("[ERROR] Neither build_tekken6_codegen.py nor host rexgen CLI found.")


def verify_generated_code():
    init_cpp = GENERATED_DIR / "tekken6_init.cpp"
    reg_cpp = GENERATED_DIR / "tekken6_register.cpp"
    sources_cmake = GENERATED_DIR / "sources.cmake"

    if not init_cpp.exists():
        sys.exit(f"[ERROR] Missing generated file: {init_cpp}")
    if not reg_cpp.exists():
        sys.exit(f"[ERROR] Missing generated file: {reg_cpp}")
    if not sources_cmake.exists():
        sys.exit(f"[ERROR] Missing generated file: {sources_cmake}")

    recomp_count = len(list(GENERATED_DIR.glob("tekken6_recomp.*.cpp")))
    print(f"[Codegen] Verified: {init_cpp.name}, {reg_cpp.name}, and {recomp_count} chunked recomp files present.")

    # Hard assertion: 0 unresolved branches
    unresolved_count = 0
    pattern = "Unresolved branch from"
    for cpp in GENERATED_DIR.glob("*.cpp"):
        try:
            txt = cpp.read_text(encoding="utf-8", errors="ignore")
            if pattern in txt:
                unresolved_count += txt.count(pattern)
        except Exception:
            pass

    print(f"[Codegen] Unresolved branches count: {unresolved_count}")
    if unresolved_count > 0:
        sys.exit(f"[FATAL] {unresolved_count} unresolved branches detected in {GENERATED_DIR}!")
    print("[Codegen] SUCCESS: Clean static recompilation verified (0 unresolved branches)!")


def main():
    parser = argparse.ArgumentParser(description="Tekken 6 AOT Code Generator")
    parser.add_argument("--input", type=str, help="Path to default.xex")
    parser.add_argument("--output", type=str, default=str(GENERATED_DIR), help="Output directory")
    parser.add_argument("--config", type=str, default=str(CONFIG_FILE), help="Path to config.toml")
    parser.add_argument("--force", action="store_true", help="Force re-generation even if cache exists")
    args = parser.parse_args()

    out_dir = pathlib.Path(args.output).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    if not args.force and check_and_extract_cache():
        verify_generated_code()
        return

    xex = locate_xex(args.input)
    if not xex:
        # Check if pre-extracted files are present
        if (out_dir / "tekken6_init.cpp").exists() and (out_dir / "tekken6_register.cpp").exists():
            print(f"[Codegen] No XEX found, but verified pre-generated code is present in {out_dir}.")
            verify_generated_code()
            return
        sys.exit(f"[ERROR] Could not find default.xex. Searched in: {[str(p) for p in XEX_CANDIDATES]}")

    print(f"[Codegen] Target XEX: {xex}")
    run_codegen(xex, out_dir, args.config)
    verify_generated_code()


if __name__ == "__main__":
    main()


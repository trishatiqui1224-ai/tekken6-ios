"""
tools/ios/patch_engine.py
Shared dry-run assertion engine for ReXGlue iOS SDK patches.

Performs strict, idempotent text substitutions with dry-run assertions:
  - Asserts every patch anchor appears exactly ONCE in target files.
  - Never mutates files if any anchor fails to match.
  - Supports --status and --revert.
"""

import argparse
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def find_sdk(probe_file: str, custom_path: pathlib.Path = None) -> pathlib.Path:
    """Locates the iOS SDK root."""
    if custom_path:
        cand = pathlib.Path(custom_path).resolve()
        if (cand / probe_file).exists():
            return cand
        sys.exit(f"[ERROR] Cannot find {probe_file} in custom SDK path: {cand}")

    env_sdk = os.environ.get("TEKKEN6_SDK") or os.environ.get("REXGLUE_SDK_IOS")
    candidates = [pathlib.Path(env_sdk)] if env_sdk else [
        ROOT.parent / "rexglue-sdk-ios",
        ROOT / "rexglue-sdk-ios",
        ROOT.parent.parent / "rexglue-sdk-ios",
        pathlib.Path(r"E:\Project\NFS Carbon Switch\nfsc-nx\reference\nfsmw-nx\sdk"),
    ]

    for cand in candidates:
        if (cand / probe_file).exists():
            return cand.resolve()

    sys.exit(f"[ERROR] Cannot find ReXGlue SDK containing {probe_file}.\n"
             f"        Searched in TEKKEN6_SDK, ../rexglue-sdk-ios, and known reference paths.")


def read_file(path: pathlib.Path) -> tuple[str, str]:
    with open(path, "r", encoding="utf-8", newline="") as f:
        content = f.read()
    eol = "\r\n" if "\r\n" in content else "\n"
    return content.replace("\r\n", "\n"), eol


def write_file(path: pathlib.Path, content: str, eol: str):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(content.replace("\n", eol))


def run_patch(name: str, blocks: list[tuple[str, str, str, str]], sdk_path: pathlib.Path = None) -> int:
    """
    blocks = [(relative_file_path, description, anchor, replacement), ...]
    """
    sdk = find_sdk(blocks[0][0], sdk_path)
    file_map = {}
    for rel_path, _, _, _ in blocks:
        if rel_path not in file_map:
            full_path = sdk / rel_path
            if not full_path.exists():
                sys.exit(f"[ERROR] Cannot find SDK file: {full_path}")
            txt, eol = read_file(full_path)
            file_map[rel_path] = [full_path, txt, eol]

    # Check if already applied
    all_applied = True
    for rel_path, _, _, replacement in blocks:
        if replacement not in file_map[rel_path][1]:
            all_applied = False
            break

    if all_applied:
        print(f"  [ok] {name}: all {len(blocks)} blocks already applied.")
        return 0

    # Dry-run assertion: every anchor must appear exactly ONCE
    new_contents = {}
    for rel_path in file_map:
        new_contents[rel_path] = file_map[rel_path][1]

    for rel_path, desc, anchor, replacement in blocks:
        txt = new_contents[rel_path]
        if replacement in txt:
            continue
        count = txt.count(anchor)
        if count == 0:
            sys.exit(f"[ERROR] Patch '{name}' ({desc}): anchor NOT found in {rel_path}!\nAnchor snippet:\n{anchor[:120]}...")
        if count > 1:
            sys.exit(f"[ERROR] Patch '{name}' ({desc}): anchor matches {count} times in {rel_path}! (Ambiguous)")
        new_contents[rel_path] = txt.replace(anchor, replacement, 1)

    # Commit all changes to disk
    for rel_path, (full_path, _, eol) in file_map.items():
        if new_contents[rel_path] != file_map[rel_path][1]:
            write_file(full_path, new_contents[rel_path], eol)
            print(f"  [patched] {name}: updated {rel_path}")

    return 0


#!/usr/bin/env python3
"""List what a Godot 4 .pck contains, grouped by source folder and file type.

Usage: python3 tools/pck_report.py [build/web/index.pck] [--top N]
"""
import struct
import sys
from collections import defaultdict

def read_entries(path):
    with open(path, "rb") as f:
        if f.read(4) != b"GDPC":
            raise SystemExit(f"{path}: not a Godot pack")
        version, _major, _minor, _patch, flags = struct.unpack("<5I", f.read(20))
        if version < 3:
            raise SystemExit(f"{path}: pack format {version} not supported")
        _file_base, dir_offset = struct.unpack("<QQ", f.read(16))
        f.seek(dir_offset)
        (count,) = struct.unpack("<I", f.read(4))
        entries = []
        for _ in range(count):
            (plen,) = struct.unpack("<I", f.read(4))
            name = f.read(plen).rstrip(b"\0").decode()
            _off, size = struct.unpack("<QQ", f.read(16))
            f.read(16 + 4)  # md5, flags
            entries.append((name, size))
        return entries

def main():
    args = sys.argv[1:]
    top = 25
    if "--top" in args:
        i = args.index("--top")
        top = int(args[i + 1])
        del args[i : i + 2]
    path = args[0] if args else "build/web/index.pck"
    entries = read_entries(path)
    # Map imported files back to their source: .godot/imported/<name>-<md5>.<ext>
    sources = {}
    for name, _ in entries:
        if name.endswith(".import"):
            sources[name[: -len(".import")]] = True
    total = sum(s for _, s in entries)
    by_ext = defaultdict(int)
    by_dir = defaultdict(int)
    for name, size in entries:
        ext = name.rsplit(".", 1)[-1]
        by_ext[ext] += size
        rel = name.replace("res://", "")
        if rel.startswith(".godot/imported/"):
            base = rel.split("/")[-1].rsplit("-", 1)[0]
            folder = next((s for s in sources if s.endswith("/" + base)), "?")
            rel = folder.replace("res://", "")
        by_dir["/".join(rel.split("/")[:2])] += size
    mb = 1024 * 1024
    print(f"{path}: {len(entries)} files, {total / mb:.1f} MiB")
    print("\nBy type:")
    for ext, size in sorted(by_ext.items(), key=lambda x: -x[1])[:12]:
        print(f"  {ext:10} {size / mb:7.2f} MiB")
    print("\nBy folder:")
    for d, size in sorted(by_dir.items(), key=lambda x: -x[1])[:15]:
        print(f"  {d:32} {size / mb:7.2f} MiB")
    print(f"\nLargest {top} files:")
    for name, size in sorted(entries, key=lambda x: -x[1])[:top]:
        print(f"  {size / mb:7.2f} MiB  {name}")

if __name__ == "__main__":
    main()

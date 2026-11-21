#!/usr/bin/env python3
"""Assert that every packaged Mach-O is arm64e-only and metadata says so."""
import os, subprocess, sys, tempfile

if len(sys.argv) != 2:
    raise SystemExit("usage: CheckArm64eOnly.py package.deb")
pkg = sys.argv[1]
control = subprocess.check_output(["dpkg-deb", "-f", pkg], text=True)
assert "Architecture: iphoneos-arm64e" in control, control
assert "Description: iOS 剪贴板管理器（arm64e单架构）。" in control, control
with tempfile.TemporaryDirectory(prefix="kayoko-arm64e-") as temp:
    subprocess.run(["dpkg-deb", "-x", pkg, temp], check=True)
    checked = 0
    for root, _, files in os.walk(temp):
        for name in files:
            path = os.path.join(root, name)
            with open(path, "rb") as stream:
                magic = stream.read(4)
            if magic not in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"):
                continue
            archs = subprocess.check_output(["xcrun", "lipo", "-archs", path], text=True).strip().split()
            assert archs == ["arm64e"], f"{path}: unexpected architectures {archs}"
            checked += 1
    assert checked == 4, f"expected four packaged Mach-O files, checked {checked}"
print(f"PASS: {checked} thin arm64e Mach-O binaries; package details explicitly say arm64e单架构")

#!/usr/bin/env python3
"""Inspect actual binaries; a preview package never becomes a release by inference."""
import argparse
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
parser.add_argument("arch", choices=["arm64", "x86_64"])
parser.add_argument("--mode", choices=["--preview", "--developer-id", "--signed"], default="--preview")
args = parser.parse_args()

def run(*argv):
    return subprocess.run(argv, text=True, capture_output=True, check=True).stdout.strip()

info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
binary = args.app / "Contents/MacOS" / info["CFBundleExecutable"]
macho_magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
binaries = []
for path in args.app.rglob("*"):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open('rb') as handle:
        if handle.read(4) in macho_magic:
            binaries.append(path)
assert binary in binaries and len(binaries) >= 2, "主程序或 Core 二进制缺失"
architectures = {str(path.relative_to(args.app)): run("lipo", "-archs", str(path)).split() for path in binaries}
assert all(value == [args.arch] for value in architectures.values()), architectures
minimum_systems = {}
binary_signatures = {}
for path in binaries:
    key = str(path.relative_to(args.app))
    versions = re.findall(r'\bminos\s+(\S+)', run("xcrun", "vtool", "-show-build", str(path)))
    assert versions and all(value == "14.0" for value in versions), (key, versions)
    minimum_systems[key] = versions
    run("codesign", "--verify", "--strict", str(path))
    details = subprocess.run(["codesign", "-dv", "--verbose=4", str(path)], text=True, capture_output=True, check=True).stderr
    assert re.search(r'flags=.*\bruntime\b', details), (key, "Hardened Runtime 未启用")
    if args.mode != "--preview":
        assert "Authority=Developer ID Application:" in details, (key, "缺少 Developer ID 签名")
    payload = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(path)], capture_output=True, check=True).stdout.strip()
    nested_entitlements = plistlib.loads(payload) if payload else {}
    assert nested_entitlements.get("com.apple.security.get-task-allow", False) is False, (key, "禁止调试授权")
    binary_signatures[key] = {"runtimeEnabled": True, "debuggingAllowed": False,
        "developerIDSigned": "Authority=Developer ID Application:" in details}
assert info["LSMinimumSystemVersion"] == "14.0", info["LSMinimumSystemVersion"]
privacy = json.loads(run(sys.executable, str(Path(__file__).with_name("check_binary_privacy.py")), str(args.app)))
run("codesign", "--verify", "--deep", "--strict", str(args.app))
signing = subprocess.run(["codesign", "-dv", "--verbose=4", str(args.app)], text=True, capture_output=True, check=True).stderr
entitlement_data = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(args.app)], capture_output=True, check=True).stdout
entitlements = plistlib.loads(entitlement_data)
assert entitlements.get("com.apple.security.automation.apple-events") is True
assert entitlements.get("com.apple.security.app-sandbox", False) is False
assert entitlements.get("com.apple.security.get-task-allow", False) is False, "发行构建不得允许调试"
assert re.search(r'flags=.*\bruntime\b', signing), "Hardened Runtime 未启用"
if args.mode != "--preview":
    assert "Authority=Developer ID Application:" in signing
if args.mode == "--signed":
    run("spctl", "--assess", "--type", "execute", "--verbose=4", str(args.app))
print(json.dumps({"version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
    "bundleID": info["CFBundleIdentifier"], "architectures": architectures,
    "binaryMinimumSystems": minimum_systems,
    "binarySignatures": binary_signatures,
    "minimumSystem": info["LSMinimumSystemVersion"], "signingMode": args.mode,
    "developerIDSigned": "Authority=Developer ID Application:" in signing,
    "notarization": "已执行并通过 Gatekeeper 检查" if args.mode == "--signed" else "未执行",
    "runtimeEnabled": "runtime" in signing,
    "entitlements": entitlements, "privacyAudit": privacy, "runtimeAcceptance": "未验证"}, ensure_ascii=False, indent=2))

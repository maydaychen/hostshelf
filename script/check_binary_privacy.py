#!/usr/bin/env python3
"""Read-only privacy gate for a macOS app or an uncompressed file.

Inspect a mounted DMG's app, not the compressed disk image itself. Findings
contain only relative filenames and counts; matched bytes are never printed.
"""
import argparse
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys


class AuditError(Exception):
    pass


class SafeArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise AuditError("invalid-arguments")


PROJECT_ROOTS = {
    str(Path(__file__).absolute().parent.parent),
    str(Path(__file__).resolve().parent.parent),
}
THIN_MAGICS = {
    b"\xce\xfa\xed\xfe": ("<", False),
    b"\xcf\xfa\xed\xfe": ("<", True),
    b"\xfe\xed\xfa\xce": (">", False),
    b"\xfe\xed\xfa\xcf": (">", True),
}
FAT_MAGICS = {
    b"\xca\xfe\xba\xbe": (">", False),
    b"\xbe\xba\xfe\xca": ("<", False),
    b"\xca\xfe\xba\xbf": (">", True),
    b"\xbf\xba\xfe\xca": ("<", True),
}


def path_counts(data):
    markers = {
        "user-home-path": {"/Users/"},
        "system-build-path": {"/var/folders/"},
        "project-root-path": PROJECT_ROOTS,
    }
    return {kind: len(re.findall(b"|".join(
        re.escape(value.encode(encoding)) for value in sorted(values)
        for encoding in ("utf-8", "utf-16-le", "utf-16-be")), data))
        for kind, values in markers.items()}


def macho_counts(data):
    """Read load commands and STAB types directly, including universal slices."""
    if data[:4] not in THIN_MAGICS and data[:4] not in FAT_MAGICS:
        return None
    totals = {"debug-source-record": 0, "debug-object-record": 0, "dwarf-segment": 0}

    def require(condition):
        if not condition:
            raise AuditError("invalid-macho")

    def thin(base, size):
        magic = data[base:base + 4]
        require(magic in THIN_MAGICS)
        endian, is64 = THIN_MAGICS[magic]
        header_size = 32 if is64 else 28
        require(size >= header_size and base + size <= len(data))
        command_count, command_bytes = struct.unpack_from(endian + "II", data, base + 16)
        pointer = base + header_size
        command_end = pointer + command_bytes
        require(command_end <= base + size and command_count <= command_bytes // 8)
        for _ in range(command_count):
            require(pointer + 8 <= command_end)
            command, command_size = struct.unpack_from(endian + "II", data, pointer)
            require(command_size >= 8 and pointer + command_size <= command_end)
            if command in (0x1, 0x19):  # LC_SEGMENT / LC_SEGMENT_64
                segment_size, section_size, count_offset = (72, 80, 64) if command == 0x19 else (56, 68, 48)
                require(command_size >= segment_size)
                section_count = struct.unpack_from(endian + "I", data, pointer + count_offset)[0]
                require(segment_size + section_count * section_size <= command_size)
                dwarf = data[pointer + 8:pointer + 24].rstrip(b"\0") == b"__DWARF"
                for index in range(section_count):
                    section = pointer + segment_size + index * section_size
                    dwarf |= data[section + 16:section + 32].rstrip(b"\0") == b"__DWARF"
                if dwarf:
                    totals["dwarf-segment"] += 1
            elif command == 0x2:  # LC_SYMTAB
                require(command_size >= 24)
                symbol_offset, symbol_count, string_offset, string_size = struct.unpack_from(
                    endian + "IIII", data, pointer + 8)
                entry_size = 16 if is64 else 12
                require(symbol_offset + symbol_count * entry_size <= size)
                require(string_offset + string_size <= size)
                for index in range(symbol_count):
                    symbol_type = data[base + symbol_offset + index * entry_size + 4]
                    if symbol_type == 0x64:  # N_SO: source file mapping
                        totals["debug-source-record"] += 1
                    elif symbol_type == 0x66:  # N_OSO: object file mapping
                        totals["debug-object-record"] += 1
            pointer += command_size
        require(pointer == command_end)

    if data[:4] in THIN_MAGICS:
        thin(0, len(data))
    else:
        endian, fat64 = FAT_MAGICS[data[:4]]
        require(len(data) >= 8)
        count = struct.unpack_from(endian + "I", data, 4)[0]
        entry_size = 32 if fat64 else 20
        table_end = 8 + count * entry_size
        require(count > 0 and table_end <= len(data))
        for index in range(count):
            pointer = 8 + index * entry_size
            offset, size = struct.unpack_from(endian + ("QQ" if fat64 else "II"), data, pointer + 8)
            require(offset >= table_end and offset + size <= len(data))
            thin(offset, size)
    return totals


def audit(target):
    target = target.resolve(strict=True)
    is_app = target.is_dir() and target.suffix == ".app"
    if not is_app and not target.is_file():
        raise AuditError("expected-app-or-file")
    if not is_app and target.suffix.lower() in (".dmg", ".zip", ".pkg"):
        raise AuditError("mount-or-extract-archive-first")
    result = {"schemaVersion": 1, "status": "passed", "filesScanned": 0,
              "machoFilesScanned": 0, "files": [], "issues": []}
    seen = set()

    def label(path):
        value = path.relative_to(target).as_posix() if is_app else "<input-file>"
        return "<redacted-relative-path>" if any(path_counts(value.encode()).values()) else value

    def issue(path, kind, count=1):
        result["issues"].append({"file": label(path), "kind": kind, "count": count})

    def inspect(path):
        info = path.stat()
        if not stat.S_ISREG(info.st_mode):
            raise AuditError("non-regular-file")
        identity = (info.st_dev, info.st_ino)
        if identity in seen:
            return
        seen.add(identity)
        data = path.read_bytes()
        result["filesScanned"] += 1
        counts = path_counts(data)
        for kind, count in counts.items():
            if count:
                issue(path, kind, count)
        debug_counts = macho_counts(data)
        if debug_counts is not None:
            result["machoFilesScanned"] += 1
            counts.update(debug_counts)
            for kind, count in debug_counts.items():
                if count:
                    issue(path, kind, count)
        result["files"].append({"file": label(path), "macho": debug_counts is not None,
                                "counts": counts})

    if is_app:
        def walk_error(error):
            raise AuditError("directory-read-failed")

        for directory, dirs, files in os.walk(target, followlinks=False, onerror=walk_error):
            parent = Path(directory)
            for name in sorted(dirs + files):
                path = parent / name
                if path.suffix.lower() == ".dsym":
                    issue(path, "embedded-dsym")
                if path.is_symlink():
                    try:
                        resolved = path.resolve(strict=True)
                    except (OSError, RuntimeError):
                        issue(path, "broken-symlink")
                        continue
                    if not resolved.is_relative_to(target):
                        issue(path, "external-symlink")
            dirs.sort()
            for name in sorted(files):
                path = parent / name
                if not path.is_symlink():
                    inspect(path)
        if result["machoFilesScanned"] == 0:
            raise AuditError("app-has-no-macho")
    else:
        inspect(target)
    if result["issues"]:
        result["status"] = "failed"
    return result


def main():
    parser = SafeArgumentParser(prog="check_binary_privacy.py", description=__doc__)
    parser.add_argument("target", type=Path, metavar="APP_OR_FILE")
    try:
        args = parser.parse_args()
        result = audit(args.target)
    except AuditError as error:
        print(json.dumps({"schemaVersion": 1, "status": "error", "code": str(error)}))
        return 2
    except (OSError, RuntimeError, ValueError, struct.error):
        print(json.dumps({"schemaVersion": 1, "status": "error", "code": "inspection-failed"}))
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Privacy-gate regression checks using synthetic data and unexecuted binaries."""
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "script/check_binary_privacy.py"
WORK_ROOT = ROOT / ".tmp/privacy-cleanup/binary-privacy-tests"


class BinaryPrivacyCheck(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        WORK_ROOT.mkdir(parents=True, exist_ok=True)
        cls.work = tempfile.TemporaryDirectory(prefix="case-", dir=WORK_ROOT)
        cls.directory = Path(cls.work.name)
        cls.source = cls.directory / "fixture.c"
        cls.source.write_text("int main(void) { return 0; }\n")
        cls.debug_binary = cls.directory / "debug-binary"
        cls.clean_binary = cls.directory / "clean-binary"
        cls.debug_object = cls.directory / "debug-object.o"
        cls.tool("xcrun", "clang", "-g", "-O0", str(cls.source), "-o", str(cls.debug_binary))
        shutil.copyfile(cls.debug_binary, cls.clean_binary)
        cls.tool("xcrun", "strip", "-S", str(cls.clean_binary))
        cls.tool("xcrun", "clang", "-g", "-c", str(cls.source), "-o", str(cls.debug_object))

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    @staticmethod
    def tool(*arguments):
        try:
            result = subprocess.run(arguments, capture_output=True, timeout=30)
        except subprocess.TimeoutExpired:
            raise RuntimeError("Fixture tool timed out; diagnostics redacted") from None
        if result.returncode:
            raise RuntimeError("Fixture compiler/tool failed; diagnostics redacted")

    def invoke(self, *arguments):
        try:
            result = subprocess.run([sys.executable, str(CHECKER), *map(str, arguments)],
                                    capture_output=True, text=True, timeout=15)
        except subprocess.TimeoutExpired:
            raise AssertionError("Privacy checker timed out on an isolated fixture") from None
        self.assertEqual(result.stderr, "", "Checker diagnostics must stay redacted")
        self.assertNotIn(str(ROOT), result.stdout)
        self.assertNotIn("audit-user", result.stdout)
        return result.returncode, json.loads(result.stdout)

    def sample(self, name, data):
        path = self.directory / name
        path.write_bytes(data)
        return path

    def kinds(self, report):
        return {issue["kind"] for issue in report["issues"]}

    def app(self, name):
        app = self.directory / (name + ".app")
        executable = app / "Contents/MacOS/Fixture"
        executable.parent.mkdir(parents=True)
        shutil.copyfile(self.clean_binary, executable)
        return app

    def test_user_home_bytes_are_blocked_without_echoing_them(self):
        sample = self.sample("home.bin", b"prefix\0/Users/audit-user/project/File.swift\0suffix")
        code, report = self.invoke(sample)
        self.assertEqual(code, 1)
        self.assertIn("user-home-path", self.kinds(report))
        self.assertEqual(report["files"][0]["counts"]["user-home-path"], 1)

    def test_private_and_normal_system_build_paths_are_blocked(self):
        sample = self.sample("build.bin", b"/private/var/folders/aa/build.o\0/var/folders/bb/file.o")
        code, report = self.invoke(sample)
        self.assertEqual(code, 1)
        self.assertEqual(report["files"][0]["counts"]["system-build-path"], 2)

    def test_utf16_metadata_paths_are_blocked(self):
        value = "/Users/audit-user/project"
        sample = self.sample("unicode.bin", value.encode("utf-16-le") + b"\0\0" + value.encode("utf-16-be"))
        code, report = self.invoke(sample)
        self.assertEqual(code, 1)
        self.assertEqual(report["files"][0]["counts"]["user-home-path"], 2)

    def test_actual_project_root_is_blocked_and_never_echoed(self):
        sample = self.sample("root.bin", str(ROOT).encode())
        code, report = self.invoke(sample)
        self.assertEqual(code, 1)
        self.assertIn("project-root-path", self.kinds(report))

    def test_neutral_paths_and_runtime_dependencies_are_allowed(self):
        data = b"/HostShelf/Sources/File.swift\0/System/Library/Frameworks\0@rpath/Core\0/usr/lib/libSystem.B.dylib"
        code, report = self.invoke(self.sample("neutral.bin", data))
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "passed")
        self.assertTrue(all(value == 0 for value in report["files"][0]["counts"].values()))

    def test_real_linker_debug_mapping_is_rejected_before_strip(self):
        code, report = self.invoke(self.debug_binary)
        self.assertEqual(code, 1)
        self.assertIn("debug-object-record", self.kinds(report))
        self.assertIn("debug-source-record", self.kinds(report))

    def test_real_stripped_binary_passes(self):
        code, report = self.invoke(self.clean_binary)
        self.assertEqual(code, 0)
        self.assertEqual(report["machoFilesScanned"], 1)
        self.assertTrue(all(value == 0 for value in report["files"][0]["counts"].values()))

    def test_real_dwarf_object_is_rejected(self):
        code, report = self.invoke(self.debug_object)
        self.assertEqual(code, 1)
        self.assertIn("dwarf-segment", self.kinds(report))

    def test_universal_binary_checks_both_architecture_slices(self):
        other_arch = "x86_64" if platform.machine() == "arm64" else "arm64"
        other = self.directory / "other-architecture"
        universal = self.directory / "universal-binary"
        self.tool("xcrun", "clang", "-arch", other_arch, "-g", str(self.source), "-o", str(other))
        self.tool("xcrun", "lipo", "-create", str(self.clean_binary), str(other), "-output", str(universal))
        code, report = self.invoke(universal)
        self.assertEqual(code, 1)
        self.assertIn("debug-object-record", self.kinds(report))
        self.tool("xcrun", "strip", "-S", str(other))
        self.tool("xcrun", "lipo", "-create", str(self.clean_binary), str(other), "-output", str(universal))
        code, report = self.invoke(universal)
        self.assertEqual(code, 0)
        self.assertEqual(report["machoFilesScanned"], 1)

    def test_resources_are_scanned_and_internal_symlinks_are_deduplicated(self):
        app = self.app("Resources")
        resources = app / "Contents/Resources"
        resources.mkdir()
        (resources / "neutral.txt").write_text("/HostShelf/fixture")
        (app / "Contents/MacOS/Alias").symlink_to("Fixture")
        code, report = self.invoke(app)
        self.assertEqual(code, 0)
        self.assertEqual(report["machoFilesScanned"], 1)
        self.assertEqual(report["filesScanned"], 2)
        (resources / "private.dat").write_bytes(b"/Users/audit-user/notes")
        code, report = self.invoke(app)
        self.assertEqual(code, 1)
        self.assertIn("user-home-path", self.kinds(report))

    def test_embedded_dsym_is_rejected_even_without_path_strings(self):
        app = self.app("Symbols")
        symbols = app / "Contents/Resources/Fixture.dSYM"
        symbols.mkdir(parents=True)
        (symbols / "metadata.txt").write_text("neutral")
        code, report = self.invoke(app)
        self.assertEqual(code, 1)
        self.assertIn("embedded-dsym", self.kinds(report))

    def test_internal_dsym_alias_cannot_bypass_the_gate(self):
        app = self.app("SymbolAlias")
        resources = app / "Contents/Resources"
        symbols = resources / "NeutralName"
        symbols.mkdir(parents=True)
        (symbols / "metadata.txt").write_text("neutral")
        (resources / "Fixture.dSYM").symlink_to("NeutralName")
        code, report = self.invoke(app)
        self.assertEqual(code, 1)
        self.assertIn("embedded-dsym", self.kinds(report))

    def test_external_symlink_is_rejected_without_reading_it(self):
        app = self.app("External")
        resources = app / "Contents/Resources"
        resources.mkdir()
        outside = self.sample("outside.bin", b"/Users/audit-user/private")
        (resources / "external").symlink_to(outside)
        code, report = self.invoke(app)
        self.assertEqual(code, 1)
        self.assertIn("external-symlink", self.kinds(report))
        self.assertNotIn("user-home-path", self.kinds(report))

    def test_broken_symlink_is_rejected(self):
        app = self.app("BrokenLink")
        (app / "Contents/MacOS/Broken").symlink_to("Missing")
        code, report = self.invoke(app)
        self.assertEqual(code, 1)
        self.assertIn("broken-symlink", self.kinds(report))

    def test_non_regular_resource_fails_instead_of_waiting_for_data(self):
        app = self.app("Pipe")
        resource = app / "Contents/Resources"
        resource.mkdir()
        os.mkfifo(resource / "fifo")
        code, report = self.invoke(app)
        self.assertEqual(code, 2)
        self.assertEqual(report["code"], "non-regular-file")

    def test_bad_inputs_fail_without_path_diagnostics(self):
        for arguments in ((), (self.directory / "missing",), ("--unknown", self.directory),
                          (self.sample("broken.bin", b"\xcf\xfa\xed\xfe"),),
                          (self.sample("archive.dmg", b"neutral"),)):
            with self.subTest(argumentCount=len(arguments)):
                code, report = self.invoke(*arguments)
                self.assertEqual(code, 2)
                self.assertEqual(report["status"], "error")

    def test_empty_app_cannot_silently_pass(self):
        app = self.directory / "Empty.app"
        app.mkdir()
        code, report = self.invoke(app)
        self.assertEqual(code, 2)
        self.assertEqual(report["code"], "app-has-no-macho")


if __name__ == "__main__":
    unittest.main(verbosity=2)

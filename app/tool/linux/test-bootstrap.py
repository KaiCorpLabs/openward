#!/usr/bin/env python3
"""Exercise the actual bootstrap before any downloaded fixture may run."""
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
PINS = Path(__file__).with_name('toolchain-pins.sh')


class BootstrapTests(unittest.TestCase):
    def run_bootstrap(self, arch='x86_64', bad=None):
        with tempfile.TemporaryDirectory(prefix='openward bootstrap ') as tmp:
            root = Path(tmp)
            context = root / 'context'
            tools = root / 'bin'
            context.mkdir()
            tools.mkdir()
            trace = root / 'trace'
            init = b'#!/bin/sh\necho rustup-executed >> "$BOOTSTRAP_TRACE"\n'
            archive = b'a controlled archive fixture\n'
            pins = PINS.read_text()
            pins = re.sub(r'RUSTUP_SHA256=[0-9a-f]+',
                          'RUSTUP_SHA256=' + hashlib.sha256(init).hexdigest(), pins)
            if bad == 'rustup':
                pins = re.sub(r'RUSTUP_SHA256=[0-9a-f]+', 'RUSTUP_SHA256=' + '0' * 64, pins)
            (context / 'toolchain-pins.sh').write_text(pins)
            shutil.copy(Path(__file__).with_name('install-tools.sh'), context)
            zig = (ROOT / '.github/scripts/install-zig.sh').read_text()
            checksum = '0' * 64 if bad == 'zig' else hashlib.sha256(archive).hexdigest()
            zig = re.sub(r'sha=[0-9a-f]+', 'sha=' + checksum, zig)
            (context / 'install-zig.sh').write_text(zig)
            (root / 'init').write_bytes(init)
            (root / 'archive').write_bytes(archive)
            fakes = {
                'uname': 'case "$1" in -m) echo "$TEST_ARCH";; -s) echo Linux;; esac',
                'curl': 'echo curl >> "$BOOTSTRAP_TRACE"\n'
                        'case "${!#}" in *rustup-init) cp "$TEST_ROOT/init" "$2";; '
                        '*) cp "$TEST_ROOT/archive" "$2";; esac',
                'tar': 'echo extracted >> "$BOOTSTRAP_TRACE"\n'
                       'dir="${2%.tar.xz}"\nmkdir -p "$dir"\n'
                       'printf \'#!/bin/sh\\necho 0.16.0\\n\' > "$dir/zig"\nchmod +x "$dir/zig"',
                'git': 'if [[ "$1" == clone ]]; then\n'
                       '  mkdir -p "${!#}/bin"\n'
                       '  printf \'#!/bin/sh\\necho sdk-executed >> "$BOOTSTRAP_TRACE"\\n\' > "${!#}/bin/flutter"\n'
                       '  chmod +x "${!#}/bin/flutter"\n'
                       'else echo "$TEST_FLUTTER_HEAD"; fi',
            }
            if not shutil.which('sha256sum'):
                fakes['sha256sum'] = 'exec shasum -a 256 "$@"'
            for name, body in fakes.items():
                path = tools / name
                path.write_text('#!/bin/bash\nset -e\n' + body + '\n')
                path.chmod(0o755)
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                       BOOTSTRAP_TRACE=str(trace), TEST_ROOT=str(root), TEST_ARCH=arch,
                       TEST_FLUTTER_HEAD='0' * 40 if bad == 'flutter' else
                       re.search(r'FLUTTER_COMMIT=(\w+)', pins)[1],
                       RUST='wrong' if bad == 'version' else '1.99.0',
                       FLUTTER='3.47.6', ZIG='0.16.0')
            command = ['bash', '-c', 'bash "$1" "$2" && "$2/flutter/bin/flutter" config',
                       'test', str(context / 'install-tools.sh'), str(root / 'prefix')]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            return result.returncode, trace.read_text().splitlines() if trace.exists() else [], result.stderr

    def test_reviewed_tools_run_for_both_linux_architectures(self):
        for arch in ['x86_64', 'aarch64']:
            with self.subTest(arch=arch):
                code, trace, error = self.run_bootstrap(arch)
                self.assertEqual(code, 0, error)
                self.assertEqual(trace, ['curl', 'rustup-executed', 'curl', 'extracted', 'sdk-executed'])

    def test_unreviewed_installer_never_executes(self):
        code, trace, _ = self.run_bootstrap(bad='rustup')
        self.assertNotEqual(code, 0)
        self.assertEqual(trace, ['curl'])

    def test_bad_zig_archive_is_not_extracted(self):
        code, trace, _ = self.run_bootstrap(bad='zig')
        self.assertNotEqual(code, 0)
        self.assertNotIn('extracted', trace)
        self.assertNotIn('sdk-executed', trace)

    def test_moved_flutter_tag_never_runs_the_sdk(self):
        code, trace, _ = self.run_bootstrap(bad='flutter')
        self.assertNotEqual(code, 0)
        self.assertNotIn('sdk-executed', trace)

    def test_version_drift_fails_before_downloads(self):
        code, trace, _ = self.run_bootstrap(bad='version')
        self.assertNotEqual(code, 0)
        self.assertEqual(trace, [])

    def test_unsupported_architecture_fails_before_downloads(self):
        code, trace, _ = self.run_bootstrap('riscv64')
        self.assertNotEqual(code, 0)
        self.assertEqual(trace, [])


if __name__ == '__main__':
    unittest.main()

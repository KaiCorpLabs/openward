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
            init = b'#!/bin/sh\nset -e\ntest -f "$(dirname "$0")/dist/rust/dist/channel-rust-1.99.0.toml"\necho rustup-executed >> "$BOOTSTRAP_TRACE"\n'
            archive = b'a controlled archive fixture\n'
            pins = PINS.read_text()
            pins = re.sub(r'RUSTUP_SHA256=[0-9a-f]+',
                          'RUSTUP_SHA256=' + hashlib.sha256(init).hexdigest(), pins)
            if bad == 'rustup':
                pins = re.sub(r'RUSTUP_SHA256=[0-9a-f]+', 'RUSTUP_SHA256=' + '0' * 64, pins)
            pins = re.sub(r'RUST_MANIFEST_SHA256=[0-9a-f]+',
                          'RUST_MANIFEST_SHA256=' + ('0' * 64 if bad == 'rust-manifest'
                          else hashlib.sha256(archive).hexdigest()), pins)
            (context / 'toolchain-pins.sh').write_text(pins)
            shutil.copy(Path(__file__).with_name('install-tools.sh'), context)
            shutil.copy(Path(__file__).with_name('serve-tools.py'), context)
            for source in Path(__file__).parent.glob('*.sha256'):
                content = source.read_text()
                content = re.sub(r'^[0-9a-f]{64}', hashlib.sha256(archive).hexdigest(), content, flags=re.M)
                if bad in ('rust-component', 'dart', 'engine'):
                    match = {'rust-component': 'rustc-', 'dart': 'dart-sdk-', 'engine': '-release/'}[bad]
                    content = '\n'.join('0' * 64 + line[64:] if match in line else line for line in content.splitlines()) + '\n'
                (context / source.name).write_text(content)
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
                'python3': 'echo http://127.0.0.1:12345 > "$3"\nexec sleep 60',
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
            command = ['bash', '-c', 'bash "$1" "$2"',
                       'test', str(context / 'install-tools.sh'), str(root / 'prefix')]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            return result.returncode, trace.read_text().splitlines() if trace.exists() else [], result.stderr

    def test_reviewed_tools_run_for_both_linux_architectures(self):
        for arch in ['x86_64', 'aarch64']:
            with self.subTest(arch=arch):
                code, trace, error = self.run_bootstrap(arch)
                self.assertEqual(code, 0, error)
                self.assertEqual(trace.count('rustup-executed'), 1)
                self.assertEqual(trace.count('extracted'), 1)
                self.assertEqual(trace.count('sdk-executed'), 2)
                self.assertLess(trace.index('rustup-executed'), trace.index('sdk-executed'))

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

    def test_correct_installer_cannot_bless_a_replaced_manifest_or_compiler(self):
        for bad in ['rust-manifest', 'rust-component']:
            with self.subTest(bad=bad):
                code, trace, _ = self.run_bootstrap(bad=bad)
                self.assertNotEqual(code, 0)
                self.assertNotIn('rustup-executed', trace)
                self.assertNotIn('extracted', trace)

    def test_correct_flutter_commit_cannot_bless_replaced_executables(self):
        for bad in ['dart', 'engine']:
            with self.subTest(bad=bad):
                code, trace, _ = self.run_bootstrap(bad=bad)
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

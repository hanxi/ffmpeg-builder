import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "build-release-assets.py"


class ReleaseAssetsTest(unittest.TestCase):
    def test_manifest_rejects_missing_source_sha(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                ["python3", str(SCRIPT), "--target", "linux-x86_64", "--output-dir", directory],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("source-commit", result.stderr)

    def test_packages_and_records_executable_digests(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("ffmpeg", "ffprobe"):
                path = root / name
                path.write_text("#!/bin/sh\necho 'ffmpeg version 8.0.1'\n")
                path.chmod(path.stat().st_mode | stat.S_IXUSR)
            output = root / "out"
            subprocess.run(
                [
                    "python3", str(SCRIPT), "--target", "linux-x86_64", "--source-commit", "a" * 40,
                    "--release-tag", "dev", "--channel", "dev", "--ffmpeg", str(root / "ffmpeg"),
                    "--ffprobe", str(root / "ffprobe"), "--output-dir", str(output),
                ],
                check=True,
            )
            manifest = json.loads((output / "manifest.json").read_text())
            self.assertEqual(manifest["assets"][0]["target"], "linux-x86_64")
            self.assertEqual(len(manifest["assets"][0]["sha256"]), 64)
            self.assertTrue((output / "checksums.txt").read_text().strip())


if __name__ == "__main__":
    unittest.main()

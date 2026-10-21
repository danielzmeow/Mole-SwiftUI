#!/usr/bin/env python3
"""Exercise the local CLI override receipt without invoking builds or signing."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import stage_cli


class SourceReceiptTests(unittest.TestCase):
    def stage(self, overrides, changed, untracked=()):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "macos").mkdir()
            (root / "mole").write_text('VERSION="1.62.0"\n')
            (root / "bin").mkdir()
            (root / "bin/preview.sh").write_bytes(b"reviewed\n")
            contract = {"version": "1.62.0", "sourceCommit": "fixture", "sourceOverrides": overrides}
            (root / "macos/Compatibility.json").write_text(json.dumps(contract))
            outputs = ["\n".join(changed).encode(), "\n".join(untracked).encode(), b"mole\0"]
            with patch.object(stage_cli, "ROOT", root), patch.object(stage_cli.subprocess, "check_output", side_effect=outputs), patch.object(stage_cli.subprocess, "run"), patch.object(stage_cli.shutil, "which", return_value="go"):
                stage_cli.main()
            return (root / "dist/MoleShell.app/Contents/Resources/CLI/bin/preview.sh").exists()

    def test_reviewed_untracked_extension_is_bundled(self):
        receipt = {"bin/preview.sh": hashlib.sha256(b"reviewed\n").hexdigest()}
        self.assertTrue(self.stage(receipt, [], ["bin/preview.sh"]))

    def test_changed_override_fails_closed(self):
        with self.assertRaisesRegex(RuntimeError, "changed since review"):
            self.stage({"bin/preview.sh": "stale"}, ["bin/preview.sh"])

    def test_unreviewed_source_drift_fails_closed(self):
        with self.assertRaisesRegex(RuntimeError, "Unreviewed CLI source drift"):
            self.stage({}, ["bin/preview.sh"])

    def test_untracked_source_without_receipt_fails_closed(self):
        with self.assertRaisesRegex(RuntimeError, "Unreviewed CLI source drift"):
            self.stage({}, [], ["bin/preview.sh"])


if __name__ == "__main__":
    unittest.main()

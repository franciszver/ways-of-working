"""Tests for taskrepo.cli."""

import io
import os
import tempfile
import unittest
from contextlib import redirect_stdout

from taskrepo.cli import main


class CliTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.tmpdir.name, "db.json")

    def tearDown(self):
        self.tmpdir.cleanup()

    def _run(self, *args):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = main(["--db", self.db_path, *args])
        return code, buf.getvalue()

    def test_set_then_get(self):
        code, _ = self._run("set", "name", "alice")
        self.assertEqual(code, 0)
        code, out = self._run("get", "name")
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), "alice")

    def test_get_missing_prints_placeholder(self):
        code, out = self._run("get", "nope")
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), "(missing)")

    def test_keys_lists_set_keys(self):
        self._run("set", "a", "1")
        self._run("set", "b", "2")
        code, out = self._run("keys")
        self.assertEqual(code, 0)
        self.assertEqual(sorted(out.split()), ["a", "b"])


if __name__ == "__main__":
    unittest.main()

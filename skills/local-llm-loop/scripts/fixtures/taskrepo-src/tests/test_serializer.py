"""Tests for taskrepo.serializer."""

import unittest

from taskrepo.serializer import dumps, loads
from taskrepo.store import Store


class SerializerTests(unittest.TestCase):
    def test_roundtrip_basic_values(self):
        store = Store()
        store.set("a", 1)
        store.set("b", "text")
        data = dumps(store)
        restored = loads(data)
        self.assertEqual(restored.get("a"), 1)
        self.assertEqual(restored.get("b"), "text")

    def test_roundtrip_set_and_tuple(self):
        store = Store()
        store.set("s", {1, 2, 3})
        store.set("t", (1, "two", 3.0))
        data = dumps(store)
        restored = loads(data)
        self.assertEqual(restored.get("s"), {1, 2, 3})
        self.assertEqual(restored.get("t"), (1, "two", 3.0))

    def test_dumps_produces_json_with_entries(self):
        store = Store()
        store.set("a", 1)
        data = dumps(store)
        self.assertIn('"entries"', data)
        self.assertIn('"a"', data)


if __name__ == "__main__":
    unittest.main()

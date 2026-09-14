"""Tests for taskrepo.store.Store."""

import unittest

from taskrepo.store import Store


class FakeClock:
    """A controllable clock: advance() moves time forward deterministically."""

    def __init__(self, start=0.0):
        self.now = start

    def advance(self, seconds):
        self.now += seconds

    def __call__(self):
        return self.now


class StoreTests(unittest.TestCase):
    def test_set_and_get(self):
        store = Store()
        store.set("a", 1)
        self.assertEqual(store.get("a"), 1)

    def test_get_missing_returns_none(self):
        store = Store()
        self.assertIsNone(store.get("nope"))

    def test_ttl_expiry(self):
        clock = FakeClock()
        store = Store(clock=clock)
        store.set("a", "value", ttl=10)
        self.assertEqual(store.get("a"), "value")
        clock.advance(11)
        self.assertIsNone(store.get("a"))

    def test_delete(self):
        store = Store()
        store.set("a", 1)
        store.delete("a")
        self.assertIsNone(store.get("a"))
        store.delete("nonexistent")  # should not raise

    def test_keys_excludes_expired(self):
        clock = FakeClock()
        store = Store(clock=clock)
        store.set("a", 1, ttl=5)
        store.set("b", 2)
        clock.advance(6)
        self.assertEqual(store.keys(), ["b"])

    def test_is_expired(self):
        clock = FakeClock()
        store = Store(clock=clock)
        store.set("a", 1, ttl=5)
        self.assertFalse(store.is_expired("a"))
        clock.advance(6)
        self.assertTrue(store.is_expired("a"))
        self.assertFalse(store.is_expired("nonexistent"))


if __name__ == "__main__":
    unittest.main()

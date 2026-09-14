"""In-memory key-value store with per-key TTL expiry."""

import time


class Store:
    """A dict-like store where entries can expire after a TTL."""

    def __init__(self, clock=time.monotonic):
        self._clock = clock
        self._data = {}  # key -> (value, expires_at_or_None)

    def set(self, key, value, ttl=None):
        """Set key to value. ttl is seconds until expiry, or None for no expiry."""
        expires_at = None
        if ttl is not None:
            expires_at = self._clock() + ttl
        self._data[key] = (value, expires_at)

    def get(self, key):
        """Return the value for key, or None if missing or expired."""
        entry = self._data.get(key)
        if entry is None:
            return None
        value, expires_at = entry
        if expires_at is not None and self._clock() >= expires_at:
            del self._data[key]
            return None
        return value

    def delete(self, key):
        """Remove key if present. No error if absent."""
        self._data.pop(key, None)

    def keys(self):
        """Return a list of all non-expired keys."""
        now = self._clock()
        live = []
        for key, (value, expires_at) in list(self._data.items()):
            if expires_at is not None and now >= expires_at:
                del self._data[key]
                continue
            live.append(key)
        return live

    def raw_items(self):
        """Return the raw (key, value, expires_at) tuples, including expired ones.

        Used by the serializer so it can decide what to skip.
        """
        return [(k, v, exp) for k, (v, exp) in self._data.items()]

    def is_expired(self, key):
        """Return True if key exists in storage but has expired."""
        entry = self._data.get(key)
        if entry is None:
            return False
        _, expires_at = entry
        return expires_at is not None and self._clock() >= expires_at

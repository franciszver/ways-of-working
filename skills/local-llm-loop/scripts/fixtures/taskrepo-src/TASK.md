# Task: default value on get, and hide expired entries from snapshots

## Background

`taskrepo.store.Store.get(key)` returns `None` when `key` is missing or
expired. Callers cannot tell "missing" apart from "the key really holds
`None`", and cannot supply a fallback value.

Separately, `taskrepo.serializer.dumps(store)` snapshots every entry in
a `Store`, including entries that have already expired. An expired
entry should not appear in the snapshot at all.

## Required changes

1. In `taskrepo/store.py`, add a `default=None` parameter to
   `Store.get`. When the key is missing or expired, return `default`
   instead of always returning `None`. Existing calls to `get(key)`
   (no second argument) must keep working exactly as before.

2. In `taskrepo/serializer.py`, change `dumps` so that expired entries
   are left out of the JSON output entirely (checked using the same
   store's expiry logic, e.g. `store.is_expired(key)`).

3. Update `tests/test_store.py` and/or `tests/test_serializer.py` to
   cover the new behavior:
   - `store.get("missing", default=42) == 42`
   - `store.get("missing")` still returns `None` (no default given)
   - after a key expires, `serializer.dumps(store)` does not contain
     that key at all (e.g. checked by parsing the JSON, or by checking
     the key does not appear in the raw string).

## Why this needs two source files, not one

Editing only `store.py` (adding `default=`) does not touch
`serializer.dumps`, which still calls `store.raw_items()` directly and
copies every entry, expired or not, into the snapshot. A test that
checks an expired key is absent from `dumps()` output will fail until
`serializer.py` is also changed. Conversely, editing only
`serializer.py` does not add the `default=` parameter that other new
tests check. Both files must change, and the test files must be
updated to assert the new behavior.

## Done when

- `python3 -m unittest discover -s tests -t .` passes.
- `Store.get` accepts `default=` and returns it for missing/expired keys.
- `serializer.dumps` omits expired entries.
- The pre-existing test assertions are still present (do not delete or
  weaken them to make the suite pass).

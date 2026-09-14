"""JSON encode/decode helpers for taskrepo.Store.

Supports a small set of non-JSON-native Python types (set, tuple) via a
custom type hook, and can snapshot/restore a whole Store to/from JSON.
"""

import json

from .store import Store


def _encode_value(value):
    """Encode a single value, tagging non-JSON-native types."""
    if isinstance(value, set):
        return {"__type__": "set", "items": [_encode_value(v) for v in sorted(value, key=repr)]}
    if isinstance(value, tuple):
        return {"__type__": "tuple", "items": [_encode_value(v) for v in value]}
    if isinstance(value, list):
        return [_encode_value(v) for v in value]
    if isinstance(value, dict):
        return {k: _encode_value(v) for k, v in value.items()}
    return value


def _decode_hook(obj):
    """json.loads object_hook: reverse the tagging done by _encode_value."""
    type_tag = obj.get("__type__")
    if type_tag == "set":
        return set(obj["items"])
    if type_tag == "tuple":
        return tuple(obj["items"])
    return obj


def dumps(store):
    """Serialize a Store's entries to a JSON string.

    Each entry is recorded as {"key": ..., "value": ...}. Values are
    encoded with _encode_value so sets and tuples round-trip.
    """
    entries = []
    for key, value, _expires_at in store.raw_items():
        entries.append({"key": key, "value": _encode_value(value)})
    return json.dumps({"entries": entries})


def loads(data):
    """Deserialize a JSON string produced by dumps() into a new Store.

    Restored entries have no TTL (the snapshot is a point-in-time dump).
    """
    parsed = json.loads(data, object_hook=_decode_hook)
    store = Store()
    for entry in parsed["entries"]:
        store.set(entry["key"], entry["value"])
    return store

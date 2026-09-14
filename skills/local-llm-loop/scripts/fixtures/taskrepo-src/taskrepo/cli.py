"""Command-line front end for taskrepo.Store.

Kept intentionally tiny: set/get/dump against a JSON file used as
crude persistence between invocations.
"""

import argparse
import json
import os
import sys

from .serializer import dumps, loads
from .store import Store


def _load_store(path):
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            return loads(fh.read())
    return Store()


def _save_store(store, path):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(dumps(store))


def build_parser():
    parser = argparse.ArgumentParser(prog="taskrepo", description="Tiny TTL key-value store CLI")
    parser.add_argument("--db", default=".taskrepo.json", help="path to the JSON snapshot file")

    sub = parser.add_subparsers(dest="command", required=True)

    set_p = sub.add_parser("set", help="set a key to a string value")
    set_p.add_argument("key")
    set_p.add_argument("value")
    set_p.add_argument("--ttl", type=float, default=None, help="seconds until expiry")

    get_p = sub.add_parser("get", help="get the value for a key")
    get_p.add_argument("key")

    sub.add_parser("keys", help="list all live keys")

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)

    store = _load_store(args.db)

    if args.command == "set":
        store.set(args.key, args.value, ttl=args.ttl)
        _save_store(store, args.db)
        print(f"set {args.key!r}")
        return 0

    if args.command == "get":
        value = store.get(args.key)
        if value is None:
            print("(missing)")
        else:
            print(value)
        return 0

    if args.command == "keys":
        for key in store.keys():
            print(key)
        return 0

    parser.error(f"unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    sys.exit(main())

# taskrepo

A tiny in-memory key-value store with TTL expiry, a JSON serializer
with a custom type hook, and a small CLI. Stdlib only.

## Layout

- `taskrepo/store.py` — `Store`: set/get/delete with optional per-key TTL.
- `taskrepo/serializer.py` — `dumps`/`loads`: snapshot a `Store` to/from JSON,
  including sets and tuples via a custom type hook.
- `taskrepo/cli.py` — argparse front end: `set`, `get`, `keys` subcommands.

## Run tests

    make test

or directly:

    python3 -m unittest discover -s tests -t .

## CLI usage

    python3 -m taskrepo.cli set name alice
    python3 -m taskrepo.cli get name
    python3 -m taskrepo.cli keys

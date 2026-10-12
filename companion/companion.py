"""Explicit command entry point; no automatic enrollment or background installation."""

from fmb_companion.cli import main

if __name__ == "__main__":
    raise SystemExit(main())

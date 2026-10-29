#!/usr/bin/env python3
"""Read, validate or bump the version shared by Xcode and GitHub Releases."""
import argparse
import re
from pathlib import Path

CONFIG = Path(__file__).resolve().parents[1] / "Config/Version.xcconfig"


def validate(value: str) -> str:
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", value):
        raise ValueError("Expected a stable version such as 1.0.0 (no v prefix).")
    return value


def current() -> str:
    match = re.search(r"^MARKETING_VERSION = (.+)$", CONFIG.read_text(), re.MULTILINE)
    if not match:
        raise ValueError("MARKETING_VERSION is missing from Config/Version.xcconfig.")
    return validate(match[1].strip())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--set", metavar="VERSION")
    group.add_argument("--check-tag", metavar="TAG")
    args = parser.parse_args()
    version = current()
    try:
        if args.set:
            value = validate(args.set)
            if tuple(map(int, value.split("."))) <= tuple(map(int, version.split("."))):
                raise ValueError(f"New version must be greater than {version}.")
            CONFIG.write_text(CONFIG.read_text().replace(f"MARKETING_VERSION = {version}", f"MARKETING_VERSION = {value}", 1))
            version = value
        if args.check_tag and args.check_tag != f"v{version}":
            raise ValueError(f"Tag must be v{version}; got {args.check_tag}.")
    except ValueError as error:
        parser.error(str(error))
    print(version)


if __name__ == "__main__":
    main()

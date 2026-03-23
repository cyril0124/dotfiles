#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import pathlib
import re
import shutil
import sys
import tomllib


HEADER_RE = re.compile(r"^(?P<indent>\s*)(?P<open>\[\[?)(?P<body>.*?)(?P<close>\]\]?)(?P<trailing>\s*(?:#.*)?)$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Remove machine-specific Codex project sections from config.toml while preserving the rest of the file."
    )
    parser.add_argument("source", help="Path to the source Codex config.toml")
    parser.add_argument("destination", help="Path to the sanitized output file")
    return parser.parse_args()


def split_dotted_key(body: str) -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    in_quotes = False
    escape = False

    for char in body:
        if escape:
            current.append(char)
            escape = False
            continue

        if char == "\\" and in_quotes:
            current.append(char)
            escape = True
            continue

        if char == '"':
            current.append(char)
            in_quotes = not in_quotes
            continue

        if char == "." and not in_quotes:
            segment = "".join(current).strip()
            if segment:
                parts.append(decode_segment(segment))
            current = []
            continue

        current.append(char)

    segment = "".join(current).strip()
    if segment:
        parts.append(decode_segment(segment))

    return parts


def decode_segment(segment: str) -> str:
    if len(segment) >= 2 and segment[0] == '"' and segment[-1] == '"':
        return bytes(segment[1:-1], "utf-8").decode("unicode_escape")
    return segment


def is_absolute_project_key(key: str) -> bool:
    if not key:
        return False

    expanded = os.path.expanduser(key)
    return pathlib.PurePosixPath(expanded).is_absolute() or pathlib.PureWindowsPath(expanded).is_absolute()


def removable_project_keys(config_text: str) -> set[str]:
    data = tomllib.loads(config_text)
    projects = data.get("projects")
    if not isinstance(projects, dict):
        return set()

    removable: set[str] = set()
    for key in projects:
        if isinstance(key, str) and is_absolute_project_key(key):
            removable.add(key)

    return removable


def split_sections(config_text: str) -> list[list[str]]:
    sections: list[list[str]] = [[]]

    for line in config_text.splitlines(keepends=True):
        if HEADER_RE.match(line.rstrip("\n")) and sections[-1]:
            sections.append([line])
        else:
            sections[-1].append(line)

    return [section for section in sections if section]


def is_array_of_tables(header_match: re.Match[str]) -> bool:
    return header_match.group("open") == "[[" and header_match.group("close") == "]]"


def removable_skill_paths(config_text: str) -> set[str]:
    data = tomllib.loads(config_text)
    skills = data.get("skills")
    if not isinstance(skills, dict):
        return set()

    config_entries = skills.get("config")
    if not isinstance(config_entries, list):
        return set()

    removable: set[str] = set()
    for entry in config_entries:
        if not isinstance(entry, dict):
            continue

        path = entry.get("path")
        if isinstance(path, str) and is_absolute_project_key(path):
            removable.add(path)

    return removable


def should_remove_header(key_path: list[str], removable_keys: set[str]) -> bool:
    return len(key_path) >= 2 and key_path[0] == "projects" and key_path[1] in removable_keys


def should_remove_skill_section(section_text: str, key_path: list[str], header_match: re.Match[str], removable_skill_paths_set: set[str]) -> bool:
    if key_path != ["skills", "config"] or not is_array_of_tables(header_match) or not removable_skill_paths_set:
        return False

    try:
        data = tomllib.loads(section_text)
    except tomllib.TOMLDecodeError:
        return False

    skills = data.get("skills")
    if not isinstance(skills, dict):
        return False

    config_entries = skills.get("config")
    if not isinstance(config_entries, list) or len(config_entries) != 1:
        return False

    path = config_entries[0].get("path")
    return isinstance(path, str) and path in removable_skill_paths_set


def sanitize_text(config_text: str) -> str:
    removable_keys = removable_project_keys(config_text)
    removable_skill_paths_set = removable_skill_paths(config_text)
    if not removable_keys and not removable_skill_paths_set:
        return config_text

    output: list[str] = []

    for section in split_sections(config_text):
        first_line = section[0]
        match = HEADER_RE.match(first_line.rstrip("\n"))
        if not match:
            output.extend(section)
            continue

        key_path = split_dotted_key(match.group("body"))
        section_text = "".join(section)

        if should_remove_header(key_path, removable_keys):
            continue

        if should_remove_skill_section(section_text, key_path, match, removable_skill_paths_set):
            continue

        output.extend(section)

    return "".join(output)


def main() -> int:
    args = parse_args()

    source = pathlib.Path(args.source).expanduser()
    destination = pathlib.Path(args.destination).expanduser()

    if not source.is_file():
        print(f"Source file not found: {source}", file=sys.stderr)
        return 1

    config_text = source.read_text(encoding="utf-8")
    sanitized = sanitize_text(config_text)

    destination.parent.mkdir(parents=True, exist_ok=True)
    tmp_destination = destination.with_suffix(destination.suffix + ".tmp")
    tmp_destination.write_text(sanitized, encoding="utf-8")
    shutil.move(tmp_destination, destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

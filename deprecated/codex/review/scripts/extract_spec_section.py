#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import List, Optional, Tuple


HEADING_RE = re.compile(r"^(?P<hashes>#{1,6})\s+(?P<title>.+?)\s*$")


def _norm_title(title: str) -> str:
    return re.sub(r"\s+", " ", title.strip()).lower()


def extract_section_lines(lines: List[str], section_title: str) -> Tuple[int, int]:
    """
    Returns (start_idx, end_idx) for the section content, including its heading line.
    Matches headings case-insensitively. End is next heading of <= level, or EOF.
    """
    target = _norm_title(section_title)
    start_idx: Optional[int] = None
    start_level: Optional[int] = None

    for i, line in enumerate(lines):
        m = HEADING_RE.match(line)
        if not m:
            continue
        title = _norm_title(m.group("title"))
        if title == target:
            start_idx = i
            start_level = len(m.group("hashes"))
            break

    if start_idx is None or start_level is None:
        raise ValueError(f'Section not found: "{section_title}"')

    end_idx = len(lines)
    for i in range(start_idx + 1, len(lines)):
        m = HEADING_RE.match(lines[i])
        if not m:
            continue
        level = len(m.group("hashes"))
        if level <= start_level:
            end_idx = i
            break

    return start_idx, end_idx


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract a markdown section by heading title.")
    parser.add_argument("path", help="Path to a markdown spec doc.")
    parser.add_argument("--section", help="Markdown heading title to extract (case-insensitive).")
    parser.add_argument(
        "--print-range",
        action="store_true",
        help="Print the 1-based line range to stderr as 'start:end' (informational).",
    )
    args = parser.parse_args()

    path = Path(args.path)
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)

    if not args.section:
        sys.stdout.write(text)
        return 0

    start_idx, end_idx = extract_section_lines(lines, args.section)
    if args.print_range:
        print(f"{start_idx + 1}:{end_idx}", file=sys.stderr)
    sys.stdout.write("".join(lines[start_idx:end_idx]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

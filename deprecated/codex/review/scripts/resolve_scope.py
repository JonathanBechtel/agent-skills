#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Tuple


@dataclass(frozen=True)
class Scope:
    mode: str  # working_tree | files | commit
    files: List[str]
    commit: Optional[str]
    spec_path: Optional[str]
    spec_section: Optional[str]


def _run(cmd: List[str]) -> str:
    proc = subprocess.run(cmd, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"Command failed ({proc.returncode}): {shlex.join(cmd)}\n{proc.stderr.strip()}")
    return proc.stdout


def _git_root() -> Path:
    out = _run(["git", "rev-parse", "--show-toplevel"]).strip()
    return Path(out)


def _is_git_repo() -> bool:
    try:
        _run(["git", "rev-parse", "--is-inside-work-tree"])
        return True
    except Exception:
        return False


def _normalize_paths(paths: Iterable[str]) -> List[str]:
    root = _git_root()
    normalized: List[str] = []
    for raw in paths:
        p = Path(raw)
        if not p.is_absolute():
            p = (Path.cwd() / p).resolve()
        try:
            rel = p.relative_to(root)
        except ValueError:
            # Outside repo; keep as provided (rare, but don't crash).
            normalized.append(raw)
            continue
        normalized.append(str(rel))
    return sorted(set(normalized))


def _list_uncommitted_files() -> List[str]:
    staged = _run(["git", "diff", "--name-only", "--cached"]).splitlines()
    unstaged = _run(["git", "diff", "--name-only"]).splitlines()
    untracked = _run(["git", "ls-files", "--others", "--exclude-standard"]).splitlines()
    files = [f for f in staged + unstaged + untracked if f.strip()]
    return sorted(set(files))


def _list_commit_files(commit_or_range: str) -> List[str]:
    # Accept single commit or any rev range supported by git diff.
    # For a single commit, prefer <sha>^! which works even for merges.
    is_range = (".." in commit_or_range) or ("..." in commit_or_range)
    diff_target = commit_or_range if is_range else f"{commit_or_range}^!"
    out = _run(["git", "diff", "--name-only", diff_target])
    return sorted({line for line in out.splitlines() if line.strip()})


def _ref_exists(ref: str) -> bool:
    proc = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", ref],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return proc.returncode == 0


def _default_base_ref() -> str:
    for candidate in ["main", "master", "origin/main", "origin/master"]:
        if _ref_exists(candidate):
            return candidate
    raise RuntimeError("Could not infer a base branch; pass --base <ref> (e.g. --base main).")


def _current_branch_ref() -> str:
    # Returns branch name (e.g. feature/foo). Falls back to HEAD if detached.
    proc = subprocess.run(
        ["git", "symbolic-ref", "--quiet", "--short", "HEAD"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    branch = proc.stdout.strip()
    return branch if branch else "HEAD"


def _expand_files_args(paths: List[str]) -> List[str]:
    root = _git_root()
    expanded: List[str] = []
    for raw in paths:
        p = (Path.cwd() / raw).resolve() if not Path(raw).is_absolute() else Path(raw)
        if p.is_dir():
            # Prefer tracked files if possible (avoids venv, build artifacts, etc.).
            rel = str(p.relative_to(root)) if root in p.parents or p == root else raw
            try:
                tracked = _run(["git", "ls-files", "--", rel]).splitlines()
                expanded.extend([t for t in tracked if t.strip()])
            except Exception:
                expanded.extend(
                    [
                        str(fp.relative_to(root))
                        for fp in p.rglob("*")
                        if fp.is_file() and not fp.name.startswith(".")
                    ]
                )
        else:
            expanded.append(raw)
    return _normalize_paths(expanded)


def _split_spec_section(spec_arg: str) -> Tuple[str, Optional[str]]:
    # Supports: path#"Section Name" (quotes optional but recommended)
    if "#\"" in spec_arg:
        path, rest = spec_arg.split("#\"", 1)
        section = rest.rstrip("\"")
        return path, section
    if "#'" in spec_arg:
        path, rest = spec_arg.split("#'", 1)
        section = rest.rstrip("'")
        return path, section
    return spec_arg, None


def _parse_args(argv: List[str]) -> Tuple[argparse.Namespace, List[str]]:
    parser = argparse.ArgumentParser(
        description="Resolve /review scope into a concrete file list and optional spec section.",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument("--files", nargs="+", help="Paths to review (files or directories).")
    parser.add_argument("--commit", help="Commit SHA or git diff range (e.g. HEAD~3..HEAD).")
    parser.add_argument(
        "--branch",
        action="store_true",
        help="Review changes on the current branch vs a base ref (default base inferred; override with --base).",
    )
    parser.add_argument("--base", help="Base ref for --branch (e.g. main).")
    parser.add_argument("--head", help="Head ref for --branch (default: current branch/HEAD).")
    parser.add_argument(
        "--format",
        choices=["json", "lines"],
        default="json",
        help="Output format (default: json).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Deprecated alias for --format json.",
    )
    parser.add_argument(
        "--lines",
        action="store_true",
        help="Alias for --format lines.",
    )
    parser.add_argument(
        "spec",
        nargs="?",
        help='Optional spec path, optionally with section like docs/spec.md#"Section"',
    )
    # Allow passing an entire `/review ...` line (copy/paste from chat).
    if argv and argv[0].strip() == "/review":
        argv = argv[1:]
    known, unknown = parser.parse_known_args(argv)
    return known, unknown


def resolve_scope(argv: List[str]) -> Scope:
    if not _is_git_repo():
        raise RuntimeError("Not inside a git repository; cannot resolve default scope.")

    args, unknown = _parse_args(argv)
    if unknown:
        raise RuntimeError(f"Unknown args: {unknown}")

    spec_path: Optional[str] = None
    spec_section: Optional[str] = None
    if args.spec:
        spec_path, spec_section = _split_spec_section(args.spec)
        spec_path = str(Path(spec_path))

    selected = [bool(args.commit), bool(args.files), bool(args.branch)]
    if sum(selected) > 1:
        raise RuntimeError(
            "Choose only one of --commit, --files, or --branch (you can combine any of them with a spec)."
        )

    if (args.base or args.head) and not args.branch:
        raise RuntimeError("--base/--head can only be used with --branch.")

    if args.commit:
        files = _list_commit_files(args.commit)
        return Scope(mode="commit", files=files, commit=args.commit, spec_path=spec_path, spec_section=spec_section)

    if args.files:
        files = _expand_files_args(args.files)
        return Scope(mode="files", files=files, commit=None, spec_path=spec_path, spec_section=spec_section)

    if args.branch:
        base = args.base or _default_base_ref()
        head = args.head or _current_branch_ref()
        diff_target = f"{base}...{head}"
        files = _list_commit_files(diff_target)
        return Scope(mode="commit", files=files, commit=diff_target, spec_path=spec_path, spec_section=spec_section)

    files = _list_uncommitted_files()
    return Scope(mode="working_tree", files=files, commit=None, spec_path=spec_path, spec_section=spec_section)


def main() -> int:
    try:
        scope = resolve_scope(sys.argv[1:])
    except Exception as e:
        print(str(e), file=sys.stderr)
        return 2

    args, _ = _parse_args(sys.argv[1:])
    fmt = args.format
    if args.json:
        fmt = "json"
    if args.lines:
        fmt = "lines"

    if fmt == "json":
        print(json.dumps(scope.__dict__, indent=2, sort_keys=True))
        return 0

    for f in scope.files:
        print(f)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

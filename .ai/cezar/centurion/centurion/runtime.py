"""The entry script and the per-run runtime snapshot (see layout.RUNTIME)."""

import shutil
from pathlib import Path

from . import layout

ENTRY_TEXT = '''#!/usr/bin/env python3
# centurion entry point. Written by `run.py vendor`; do not edit.
# https://github.com/glothriel/centurion
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # no __pycache__ in the work tree
sys.path.insert(0, str(Path(__file__).resolve().parent))
from centurion.cli import main  # noqa: E402

sys.exit(main(entry=Path(__file__).resolve()))
'''

PACKAGE = Path(__file__).resolve().parent


def find_root(entry: Path):
    """The repository root of an entry script: the directory whose HOME contains it."""
    for p in entry.parents:
        home = p / layout.HOME
        if home.is_dir() and (home == entry.parent or home in entry.parents):
            return p
    return None


def is_snapshot():
    return PACKAGE.parent.name == "runtime" and PACKAGE.parent.parent.name == "state"


def take_snapshot(ctx):
    """Copy the running package, the entry, the project settings, VERSION and the rules file to
    the state dir. A no-op when already running from a snapshot."""
    rt = ctx.root / layout.RUNTIME
    if is_snapshot():
        return False
    if rt.exists():
        shutil.rmtree(rt)
    rt.mkdir(parents=True)
    shutil.copytree(PACKAGE, rt / "centurion", ignore=shutil.ignore_patterns("__pycache__"))
    (rt / "run.py").write_text(ENTRY_TEXT)
    project = ctx.root / layout.PROJECT_FILE
    if project.exists():
        shutil.copy2(project, rt / "project.py")
    (rt / "VERSION").write_text(ctx.version + "\n")
    rules = ctx.root / ctx.project.rules_file
    if rules.is_file():
        shutil.copy2(rules, rt / "rules.md")
    else:
        (rt / "rules.md").write_text(f"(This repository has no rules file `{ctx.project.rules_file}`.)\n")
    exclude_state(ctx)
    return True


def exclude_state(ctx):
    """Keep the state dir ignored even on branches whose .gitignore predates centurion: the task
    loop resets to such branches, and `git add -A` (or cezar's autosave) must never pick it up."""
    path = Path(ctx.gitq("rev-parse", "--git-path", "info/exclude"))
    if not path.is_absolute():
        path = ctx.root / path
    line = f"/{layout.STATE}/"
    text = path.read_text() if path.exists() else ""
    if line not in text.splitlines():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text + ("" if not text or text.endswith("\n") else "\n") + line + "\n")

"""What every step works with: the repository root, the project settings, the environment, GitHub,
git and the run state."""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

from . import layout
from .github import GitHub, gh_cli


class StepError(Exception):
    """A step failed for a reason worth showing in the node's output (stdout), exit `code`."""

    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


class GitError(Exception):
    def __init__(self, args, proc):
        super().__init__(f"git {' '.join(args)}: exit {proc.returncode}: {proc.stderr.strip()}")
        self.proc = proc


class State:
    """state.json: the scripts' memory within one run (issue, feature branch, task, rounds...)."""

    def __init__(self, path: Path):
        self.path = path
        self.data = json.loads(path.read_text()) if path.exists() else {}

    def get(self, key, default=None):
        return self.data.get(key, default)

    def __getitem__(self, key):
        if key not in self.data:
            raise StepError(f"run state has no {key!r} (is this step running in the right workflow?)")
        return self.data[key]

    def __contains__(self, key):
        return key in self.data

    def update(self, **values):
        self.data.update(values)
        self.save()

    def drop(self, *keys):
        for k in keys:
            self.data.pop(k, None)
        self.save()

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self.data, indent=2, sort_keys=True) + "\n")


class Ctx:
    def __init__(self, root, project, env=None, gh_run=None, out=None, sleep=time.sleep, version="dev"):
        self.root = Path(root)
        self.project = project
        self.env = dict(os.environ if env is None else env)
        self.out = out or sys.stdout
        self.sleep = sleep
        self.version = version
        self.state_dir = self.root / layout.STATE
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.state = State(self.state_dir / "state.json")
        self._gh_run = gh_run
        self._gh = None

    # ---- output
    def say(self, *lines):
        for line in lines:
            print(line, file=self.out)
        self.out.flush()

    # ---- environment
    def need_env(self, name, why):
        v = self.env.get(name)
        if not v:
            raise StepError(f"no {name}: {why}")
        return v

    def repo(self):
        repo = self.env.get("CEZ_GITHUB_REPO")
        if repo:
            return repo
        # Outside a cezar run: the GitHub repository of origin.
        url = self.git("remote", "get-url", "origin", check=False).strip()
        m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", url)
        if not m:
            raise StepError("no GitHub repository for this run (CEZ_GITHUB_REPO)")
        return m.group(1)

    @property
    def gh(self) -> GitHub:
        if self._gh is None:
            self._gh = GitHub(self.repo(), self._gh_run or gh_cli(self.env))
        return self._gh

    def target(self):
        """The issue or PR comments go to: CENTURION_PR, the PR this run works on once there is
        one, else the issue or PR the run was started for."""
        if self.env.get("CENTURION_PR"):
            return int(self.env["CENTURION_PR"])
        if self.state.get("pr"):
            return int(self.state["pr"])
        return int(self.need_env("CEZ_GITHUB_NUMBER", "no GitHub issue or PR for this run"))

    # ---- files in the state dir
    def path(self, name) -> Path:
        return self.state_dir / name

    def read(self, name, default=None):
        p = self.path(name)
        if not p.exists():
            if default is not None:
                return default
            raise StepError(f"missing {layout.STATE}/{name}")
        return p.read_text()

    def write(self, name, text):
        p = self.path(name)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    def remove(self, *names):
        for n in names:
            p = self.path(n)
            if p.exists():
                p.unlink()

    # ---- git
    def git(self, *args, check=True, input=None, env=None):
        full_env = dict(self.env)
        if env:
            full_env.update(env)
        p = subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True,
                           input=input, env=full_env)
        if check and p.returncode:
            raise GitError(args, p)
        return p.stdout

    def gitq(self, *args, **kw):
        return self.git(*args, **kw).strip()

    def git_ok(self, *args):
        p = subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True, env=self.env)
        return p.returncode == 0

    def git_ok_input(self, input, *args):
        p = subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True, env=self.env, input=input)
        return p.returncode == 0

    def head(self):
        return self.gitq("rev-parse", "HEAD")

    def main_base(self):
        """origin/<main branch>: what feature branches start from and finally merge into."""
        p = subprocess.run(["git", "rev-parse", "-q", "--verify", "--abbrev-ref", "origin/HEAD"],
                           cwd=self.root, capture_output=True, text=True, env=self.env)
        return p.stdout.strip() if p.returncode == 0 and p.stdout.strip() else "origin/master"

    def main_branch(self):
        return self.main_base().removeprefix("origin/")

    def remote_has(self, branch):
        return self.git_ok("ls-remote", "-q", "--exit-code", "origin", f"refs/heads/{branch}")

    def fetch(self, branch):
        """Fetch origin's `branch` into origin/<branch>; False when origin has no such branch."""
        return self.git_ok("fetch", "-q", "origin", f"+refs/heads/{branch}:refs/remotes/origin/{branch}")

    def push(self, ref, force=False, src="HEAD"):
        self.git("push", "-q", *(["--force"] if force else []), "origin", f"{src}:refs/heads/{ref}")

    def plan_tasks_files(self):
        """The task lists (.ai/specs/*.tasks.md) this branch adds or changes against the main
        branch, committed or not (agents check their plan before cezar commits their turn)."""
        base = self.main_base()
        if self.git_ok("rev-parse", "-q", "--verify", base):
            mb = self.gitq("merge-base", base, "HEAD")
            names = self.git("diff", "--name-only", mb, "--", layout.TASKS_GLOB).splitlines()
            names += self.git("ls-files", "--others", "--exclude-standard", "--", layout.TASKS_GLOB).splitlines()
        else:
            names = [str(p.relative_to(self.root)) for p in (self.root / layout.SPECS).glob("*.tasks.md")]
        return sorted(n for n in set(names) if n and (self.root / n).is_file())

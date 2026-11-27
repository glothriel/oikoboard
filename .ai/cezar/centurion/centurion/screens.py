"""Screenshots of the app (headless Chrome driven by shot.mjs) and publishing them on a PR.

GitHub has no API to attach images to a comment, so published PNGs are committed to a side branch
(never merged; git plumbing with a temporary index, the work tree is untouched) and the comment
links them by commit SHA."""

import functools
import glob
import http.server
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from . import layout
from .context import StepError

SHOT_JS = Path(__file__).with_name("shot.mjs")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def find_chrome(env):
    candidates = [env.get("CHROME_BIN"), shutil.which("chrome-headless-shell", path=env.get("PATH"))]
    home = env.get("HOME") or os.path.expanduser("~")
    found = sorted(glob.glob(os.path.join(home, ".local/opt/chrome-headless-shell-*/chrome-headless-shell")))
    candidates += found[-1:]
    for c in candidates:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


class _Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def take(ctx, steps_file, out_dir=None):
    """Build the app (unless SCREENS_NO_BUILD=1), serve it, run the steps in headless Chrome and
    write <out>/<name>.png (default: the state dir's screens/)."""
    steps = Path(steps_file).resolve()
    if not steps.is_file():
        raise StepError(f"no steps file {steps_file}")
    out = Path(out_dir).resolve() if out_dir else ctx.path("screens")
    chrome = find_chrome(ctx.env)
    if not chrome:
        raise StepError("no chrome-headless-shell (set CHROME_BIN)", 2)
    if ctx.env.get("SCREENS_NO_BUILD") != "1":
        ctx.project.screens_build(ctx.root)
    serve = Path(ctx.project.screens_serve_dir(ctx.root))
    if not serve.is_dir():
        raise StepError(f"nothing to serve: {serve} does not exist (build first, without SCREENS_NO_BUILD=1)")

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(_Quiet, directory=str(serve)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    web = server.server_address[1]
    cdp = free_port()
    tmp = tempfile.mkdtemp(prefix="centurion-screens-")
    browser = None
    try:
        browser = subprocess.Popen(
            [chrome, "--no-sandbox", "--disable-gpu", "--disable-crash-reporter", "--hide-scrollbars",
             f"--remote-debugging-port={cdp}", f"--user-data-dir={tmp}/profile", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{cdp}/json/version", timeout=1).read()
                break
            except OSError:
                time.sleep(0.2)
        ctx.out.flush()
        p = subprocess.run(["node", str(SHOT_JS), f"http://127.0.0.1:{cdp}", f"http://127.0.0.1:{web}/",
                            str(steps), str(out)], env=ctx.env, capture_output=True, text=True)
        ctx.say(*(p.stdout + p.stderr).splitlines())
        return p.returncode
    finally:
        if browser:
            browser.kill()
            browser.wait()
        server.shutdown()
        server.server_close()
        shutil.rmtree(tmp, ignore_errors=True)


def publish(ctx, role, optional=False):
    """Publish <state>/screens/<name>.png (not the intermediate <name>.<step>.png) on the current
    PR, with screens/captions.md on top. Without screenshots: error, or nothing with `optional`."""
    from .steps import post_comment  # avoid an import cycle

    shots = ctx.path("screens")
    pngs = sorted(p for p in shots.glob("*.png") if "." not in p.stem) if shots.is_dir() else []
    if not pngs:
        if optional:
            ctx.say("no new screenshots")
            return 0
        raise StepError(f"no screenshots in {layout.STATE}/screens: take one per changed view with "
                        f"`{layout.CMD} screens <steps.json>`")
    task = ctx.state.get("task_id") or "plan"
    n = ctx.state["issue"]
    branch = layout.SCREENS_BRANCH.format(n=n)
    prefix = f"{task}/{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}"

    fd, index = tempfile.mkstemp(prefix="centurion-index-")
    os.close(fd)
    os.unlink(index)
    idx = {"GIT_INDEX_FILE": index}
    try:
        line = ctx.gitq("ls-remote", "origin", f"refs/heads/{branch}")
        parent = line.split()[0] if line else ""
        if parent:
            ctx.fetch(branch)
            ctx.git("read-tree", parent, env=idx)
        else:
            ctx.git("read-tree", "--empty", env=idx)
        for f in pngs:
            blob = ctx.gitq("hash-object", "-w", str(f))
            ctx.git("update-index", "--add", "--cacheinfo", f"100644,{blob},{prefix}/{f.name}", env=idx)
        tree = ctx.gitq("write-tree", env=idx)
    finally:
        if os.path.exists(index):
            os.unlink(index)
    commit = ctx.gitq("commit-tree", tree, *(["-p", parent] if parent else []), "-m", f"screens: issue {n} {prefix}")
    ctx.push(branch, src=commit)

    body = []
    captions = shots / "captions.md"
    if captions.exists() and captions.stat().st_size:
        body.append(captions.read_text().rstrip("\n") + "\n")
    for f in pngs:
        body.append(f"**{f.stem}**\n\n![{f.stem}](https://raw.githubusercontent.com/{ctx.repo()}/{commit}/{prefix}/{f.name})\n")
    post_comment(ctx, role, "\n".join(body))

    kept = ctx.path("screens-published") / prefix
    kept.mkdir(parents=True, exist_ok=True)
    for f in pngs:
        shutil.move(str(f), kept / f.name)
    artifacts = ctx.env.get("CEZ_ARTIFACTS_DIR")
    if artifacts:
        Path(artifacts).mkdir(parents=True, exist_ok=True)
        for f in kept.glob("*.png"):
            shutil.copy2(f, Path(artifacts) / f.name)
    for f in shots.glob("*.png"):
        f.unlink()
    if captions.exists():
        captions.unlink()
    ctx.say(f"published {len(pngs)} screenshot(s) at {commit}")
    return 0

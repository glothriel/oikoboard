"""The workflow steps: what every check node of the generated graphs runs
(`python3 .ai/cezar/centurion/state/runtime/run.py <step> [args]`), plus a few tools for agents.

A step prints what the next node (or the agent reading its output) needs and exits 0 to take the
`pass` port. A StepError prints its message on stdout and exits non-zero (`fail` port)."""

import json
import re
import subprocess
import sys

from . import layout, plan, runtime, screens
from .context import StepError
from .github import GhError

STEPS = {}


class Step:
    def __init__(self, name, fn, usage, doc, start, tool):
        self.name, self.fn, self.usage, self.doc = name, fn, usage, doc
        self.start = start  # first step of a workflow: takes the runtime snapshot
        self.tool = tool    # used by agents or humans, not a check node


def step(name, usage="", start=False, tool=False):
    def deco(fn):
        STEPS[name] = Step(name, fn, usage, (fn.__doc__ or "").strip().splitlines()[0], start, tool)
        return fn
    return deco


def warn(msg):
    print(msg, file=sys.stderr)
    sys.stderr.flush()


# ---------------------------------------------------------------- comments, merges, labels

BANNERS = {
    "reviewer": ("CAUTION", "🔴 **REVIEWER** · {task} · round {round}"),
    "developer": ("NOTE", "🔵 **DEVELOPER** · {task}"),
    "designer": ("WARNING", "🟠 **DESIGNER** · {task} · UI mockups"),
    "planner": ("IMPORTANT", "🟣 **PLANNER** · {task}"),
    "workflow": ("TIP", "🟢 **WORKFLOW** · {task}"),
}


def banner(role, task, rounds):
    if role not in BANNERS:
        raise StepError(f"unknown role {role}", 2)
    kind, line = BANNERS[role]
    return f"> [!{kind}]\n> " + line.format(task=task, round=rounds + 1)


def post_comment(ctx, role, text, target=None):
    """One comment with a role banner: every comment is posted by the same GitHub identity."""
    task = ctx.state.get("task_id") or "plan"
    body = banner(role, task, int(ctx.state.get("rounds") or 0)) + "\n\n" + text.rstrip("\n") + "\n"
    ctx.write("comment.md", body)
    ctx.say(body.rstrip("\n"))
    ctx.gh.comment(target or ctx.target(), body)


def merge_pr(ctx, pr, method, sha=None, tries=10):
    """Merge through the API. GitHub answers 405 "Base branch was modified" for a while after a
    push, so retry; a PR that is already merged counts as done."""
    err = None
    for i in range(1, tries + 1):
        try:
            ctx.gh.merge(pr, method, sha)
            return
        except GhError as e:
            err = e
        try:
            if ctx.gh.pr_state(pr) == "MERGED":
                return
        except GhError:
            pass
        warn(f"merge of #{pr} not possible yet ({i}/{tries}): {err}")
        if i < tries:
            ctx.sleep(i * 3)
    raise StepError(f"could not merge #{pr}: {err}")


def delete_branch(ctx, branch):
    try:
        ctx.gh.delete_branch(branch)
        return True
    except GhError:
        return False


def push_work(ctx):
    """Push the run's work to its PR branch (the branch this run opened, or the PR it started for)."""
    ref = ctx.state.get("head_ref") or ctx.env.get("CEZ_PR_HEAD_REF")
    if not ref:
        ctx.say("(no PR branch: not pushing)")
        return
    ctx.push(ref)
    ctx.say(f"pushed to {ref}")


def state_file(ctx, name):
    """A file argument: relative to the state dir (absolute paths stay as they are)."""
    p = ctx.state_dir / name
    if not p.exists():
        raise StepError(f"missing {p}")
    return p


# ---------------------------------------------------------------- runtime

@step("snapshot", tool=True)
def snapshot_step(ctx, args):
    """Copy this centurion (package, project, rules) to the state dir for the rest of the run."""
    if runtime.take_snapshot(ctx):
        ctx.say(f"centurion {ctx.version}: runtime snapshot in {layout.RUNTIME}")
    else:
        ctx.say(f"centurion {ctx.version}: already running from the snapshot")


@step("version", tool=True)
def version_step(ctx, args):
    """Print the version of the running centurion."""
    ctx.say(ctx.version)


# ---------------------------------------------------------------- centurion-plan

def render_issue(n, issue, comments):
    labels = ", ".join(lbl["name"] for lbl in issue.get("labels", []))
    out = [f"# {issue['title']} (#{n})", "",
           f"Opened by @{issue['user']['login']} · {issue['state']}" + (f" · labels: {labels}" if labels else ""),
           "", (issue.get("body") or "(no description)").rstrip(), ""]
    if comments:
        out += ["## Comments", ""]
        for c in comments:
            who = c["user"]["login"]
            assoc = (c.get("author_association") or "").lower()
            out += [f"### @{who} ({assoc}, {c.get('created_at', '')})", "", (c.get("body") or "").rstrip(), ""]
    return "\n".join(out)


@step("plan-init", start=True)
def plan_init(ctx, args):
    """centurion-plan start: fetch the issue with its comments for the planner, reset the state."""
    n = int(ctx.need_env("CEZ_GITHUB_NUMBER", "centurion-plan starts from a GitHub issue"))
    issue = ctx.gh.issue(n)
    ctx.state.update(task_id="plan", rounds=0, issue=n, issue_title=issue["title"])
    ctx.write("issue.md", render_issue(n, issue, ctx.gh.issue_comments(n)))
    ctx.say(f"issue #{n}: {issue['title']}")


@step("ask-issue", "intent|plan")
def ask_issue(ctx, args):
    """Post the intent with open questions (intent) or the planner's questions (plan) on the
    issue and drop the `agent` label: adding it again after answering starts a new run."""
    kind = args[0] if args else ""
    if kind == "intent":
        text = ("> [!IMPORTANT]\n> 🟣 **PLANNER** · intent, questions before the spec\n\n"
                + ctx.read("intent.md").rstrip("\n") + "\n\n### Questions\n\n" + ctx.read("questions.md").rstrip("\n") + "\n")
    elif kind == "plan":
        text = "> [!IMPORTANT]\n> 🟣 **PLANNER** · questions before planning\n\n" + ctx.read("questions.md").rstrip("\n") + "\n"
    else:
        raise StepError("usage: ask-issue intent|plan", 2)
    text += "\nAnswer in a comment, then add the `agent` label again.\n"
    ctx.write("comment.md", text)
    ctx.say(text.rstrip("\n"))
    ctx.gh.comment(ctx.target(), text)
    ctx.gh.remove_label(ctx.state["issue"], layout.LABEL_AGENT)


@step("intent-post")
def intent_post(ctx, args):
    """The intent has no open questions: post it on the issue for the record."""
    text = ("> [!IMPORTANT]\n> 🟣 **PLANNER** · intent\n\n" + ctx.read("intent.md").rstrip("\n") + "\n\n"
            "No open questions: writing the spec and the plan. Anything off here can be corrected on the plan PR.\n")
    ctx.write("comment.md", text)
    ctx.say(text.rstrip("\n"))
    ctx.gh.comment(ctx.target(), text)


@step("validate-plan", tool=False)
def validate_plan(ctx, args):
    """Check the plan this branch adds (committed or not) against the format of prompts/planner.md."""
    files = ctx.plan_tasks_files()
    if len(files) != 1:
        ctx.say(f"expected exactly one {layout.TASKS_GLOB} added on this branch, found {len(files)}: "
                + (" ".join(files) or "none"))
        return 1
    tasks = files[0]
    spec = plan.spec_for(tasks)
    spec_path = ctx.root / spec
    errors, count = plan.check_plan(spec, spec_path.read_text() if spec_path.is_file() else None,
                                    tasks, (ctx.root / tasks).read_text(), ctx.project.spec_sections)
    if errors:
        ctx.say(*("- " + e for e in errors))
        return 1
    ctx.say(f"plan ok: {spec}, {count} task(s)")


@step("plan-files", tool=True)
def plan_files(ctx, args):
    """Print the spec and the task list this branch adds."""
    files = ctx.plan_tasks_files()
    if not files:
        ctx.say("no plan on this branch yet")
    for f in files:
        ctx.say(plan.spec_for(f), f)


@step("open-pr")
def open_pr(ctx, args):
    """Create feature/issue-<n> from the main branch (once), push the plan to its branch and open
    (or reuse) the draft plan PR into the feature branch. Not labelled yet: human reviews during
    the AI plan review trigger nothing."""
    n = ctx.state["issue"]
    feature = layout.FEATURE.format(n=n)
    ref = layout.PLAN_BRANCH.format(n=n)
    ctx.state.update(feature=feature, head_ref=ref)
    if not ctx.remote_has(feature):
        ctx.push(feature, src=ctx.gitq("rev-parse", ctx.main_base()))
    ctx.push(ref, force=True)
    pr = ctx.gh.open_pr(ref)
    if not pr:
        body = (f"Plan for #{n}, written by the cezar `centurion-plan` workflow "
                f"([centurion](https://github.com/glothriel/centurion)).\n\n"
                f"Merges into `{feature}`. After it, every task gets its own PR into `{feature}`, and `{feature}`\n"
                f"goes to `{ctx.main_branch()}` in one final PR.")
        pr = ctx.gh.create_pr(ref, feature, f"Plan: {ctx.state['issue_title']}", body, draft=True)
    ctx.state.update(pr=pr)
    ctx.say(f"PR #{pr}: {ref} -> {feature}")


def ui_touched(ctx, kind):
    paths = tuple(ctx.project.ui_paths)
    if not paths:
        return False
    if kind == "plan":
        return any(p in (ctx.root / f).read_text() for f in ctx.plan_tasks_files() for p in paths)
    return any(f.startswith(paths) for f in ctx.changed_files(ctx.state["base"]))


@step("screens-check", "plan|task")
def screens_check(ctx, args):
    """Are screenshots required? `needed` when the plan names, or the task's diff touches, a UI path."""
    if not args or args[0] not in ("plan", "task"):
        raise StepError("usage: screens-check plan|task", 2)
    ctx.say("needed" if ui_touched(ctx, args[0]) else "none")


@step("mock-base")
def mock_base(ctx, args):
    """Remember the plan commit the designer's prototype starts from."""
    ctx.state.update(mock_base=ctx.head())
    ctx.say(ctx.state["mock_base"])


@step("screens", "<steps.json> [out dir]", tool=True)
def screens_step(ctx, args):
    """Screenshot the app: build, serve, drive headless Chrome with a steps file (format in shot.mjs)."""
    if not args:
        raise StepError("usage: screens <steps.json> [out dir]", 2)
    return screens.take(ctx, args[0], args[1] if len(args) > 1 else None)


@step("screens-publish", "<role> [--optional] [--issue N] [--pr N]")
def screens_publish(ctx, args):
    """Publish the state dir's screens/*.png on the current PR (side branch + SHA-pinned links)."""
    rest = list(args)
    if not rest or rest[0].startswith("-"):
        raise StepError("usage: screens-publish <role> [--optional] [--issue N] [--pr N]", 2)
    role = rest.pop(0)
    optional = False
    while rest:
        a = rest.pop(0)
        if a == "--optional":
            optional = True
        elif a in ("--issue", "--pr") and rest:
            ctx.state.update(**{"issue" if a == "--issue" else "pr": int(rest.pop(0))})
        else:
            raise StepError(f"unknown argument {a}", 2)
    return screens.publish(ctx, role, optional)


@step("mock-save")
def mock_save(ctx, args):
    """Keep the designer's prototype on centurion-mockups/issue-<n> (never merged), then drop it
    from the plan branch. Prints what the planner needs to point the tasks at it."""
    n = ctx.state["issue"]
    base = ctx.state["mock_base"]
    branch = layout.MOCKUPS_BRANCH.format(n=n)
    ctx.git("add", "-A")
    if not ctx.git_ok("diff", "--cached", "--quiet"):
        ctx.git("commit", "-q", "-m", f"Mockup prototype for #{n} (reference only, never merged)")
    if ctx.git_ok("diff", "--quiet", base, "HEAD"):
        ctx.say("no prototype code to keep")
        ctx.state.drop("mock_branch")
    else:
        ctx.push(branch, force=True)
        ctx.state.update(mock_branch=branch)
        stat = ctx.git("diff", "--stat", base, "HEAD").splitlines()[-30:]
        ctx.say(f"prototype kept on {branch} ({ctx.gitq('rev-parse', '--short', 'HEAD')}), against the plan "
                f"commit {ctx.gitq('rev-parse', '--short', base)}:", *stat)
    ctx.git("reset", "-q", "--hard", base)


@step("mock-restore")
def mock_restore(ctx, args):
    """Before the designer reworks the mockups of a revised plan: remember the plan commit and put
    the previous prototype (without its copy of the plan) back into the work tree."""
    ctx.state.update(task_id="plan")
    ctx.git("add", "-A")
    if not ctx.git_ok("diff", "--cached", "--quiet"):
        ctx.git("commit", "-q", "-m", "Revise the plan after review")
    base = ctx.head()
    ctx.state.update(mock_base=base)
    branch = layout.MOCKUPS_BRANCH.format(n=ctx.state["issue"])
    if not ctx.remote_has(branch):
        ctx.say("no previous prototype: start from the plan")
        return
    ctx.fetch(branch)
    tip = f"origin/{branch}"
    since = ctx.gitq("merge-base", "HEAD", tip)
    diff = ctx.git("diff", "--binary", since, tip, "--", ".", f":(exclude){layout.SPECS}")
    if not diff.strip():
        ctx.say(f"the previous prototype ({branch}) has no code besides the plan: start from the plan")
        return
    if ctx.git_ok_input(diff, "apply", "--index"):
        stat = ctx.git("diff", "--cached", "--stat", base).splitlines()[-30:]
        ctx.say(f"previous prototype ({branch}) applied on top of the revised plan:", *stat)
    else:
        ctx.git("reset", "-q", "--hard", base)
        ctx.say(f"the previous prototype ({branch}) does not apply to the revised plan: start from the plan, "
                f"reading the old one with git show {tip}:<path>")


@step("remock-check")
def remock_check(ctx, args):
    """After a human review of the plan: redo the mockups? `needed` when the plan touches the UI and
    the planner asked for it (state file `mockups` says redo) or there are no mockups yet."""
    if not ui_touched(ctx, "plan"):
        ctx.say("none")
        return
    if "redo" in ctx.read("mockups", "").splitlines():
        ctx.say("needed")
        return
    ctx.say("none" if ctx.remote_has(layout.MOCKUPS_BRANCH.format(n=ctx.state["issue"])) else "needed")


@step("push")
def push_step(ctx, args):
    """Push the run's work to the PR branch."""
    push_work(ctx)


@step("post-comment", "<role> <file in the state dir>")
def post_comment_step(ctx, args):
    """Post a file as a comment with a role banner (reviewer, developer, planner, designer, workflow)."""
    if len(args) != 2:
        raise StepError("usage: post-comment <role> <file>", 2)
    post_comment(ctx, args[0], state_file(ctx, args[1]).read_text())


@step("round-guard")
def round_guard(ctx, args):
    """Count the review rounds of the current task (or the plan); fail past the maximum."""
    n = int(ctx.state.get("rounds") or 0) + 1
    ctx.state.update(rounds=n)
    task = ctx.state.get("task_id")
    top = ctx.project.max_rounds
    if n > top:
        ctx.say(f"{task}: still open after {top} review rounds")
        return 1
    ctx.say(f"{task}: review round {n}/{top}")


@step("plan-reply")
def plan_reply(ctx, args):
    """Push the revised plan and post the planner's answer to the plan review."""
    push_work(ctx)
    post_comment(ctx, "planner", state_file(ctx, "answer.md").read_text())


@step("plan-ready")
def plan_ready(ctx, args):
    """The AI plan review approved: hand the plan PR to a human (ready + stage:plan)."""
    push_work(ctx)
    pr = ctx.target()
    ctx.gh.pr_ready(pr)
    ctx.gh.add_labels(pr, layout.LABEL_PLAN)
    ctx.gh.remove_label(ctx.state["issue"], layout.LABEL_AGENT)
    post_comment(ctx, "workflow", "📋 Plan ready for your review.\n\n"
                 "- **Approve**: implementation starts, task by task, on this PR.\n"
                 "- **Request changes** or **comment**: the planner revises the spec and tasks and answers here.\n")


@step("escalate")
def escalate(ctx, args):
    """Out of review rounds or fixes: push what there is, ask a human, say how to go on."""
    task = ctx.state.get("task_id") or "?"
    n = ctx.state.get("issue", "?")
    rounds = ctx.state.get("rounds") or 0
    if task == "sync":
        # never push a half-resolved merge to the feature branch
        if ctx.git_ok("rev-parse", "-q", "--verify", "MERGE_HEAD"):
            ctx.git("merge", "--abort", check=False)
        feature = ctx.state.get("feature", "the feature branch")
        text = (f"⛔ Merging `{ctx.main_branch()}` into `{feature}` needs a human: the agent could not resolve the "
                "conflicts or get the validation green after the merge.\n\n"
                f"Merge `{ctx.main_branch()}` into `{feature}` yourself and push it, then add the `resume` label to "
                f"issue #{n}.")
        post_comment(ctx, "workflow", text, target=n)
        ctx.gh.add_labels(n, layout.LABEL_HUMAN)
        return
    ctx.git("add", "-A")
    ctx.git("commit", "-q", "-m", f"{task}: work in progress", check=False)
    push_work(ctx)
    head = f"⛔ stuck on {task} after {rounds} review round(s). The exchange so far is in the comments above."
    has_pr = bool(ctx.state.get("pr") or ctx.env.get("CEZ_PR_HEAD_REF"))
    target = ctx.target()
    ref = ctx.state.get("head_ref") or "this branch"
    if task == "plan" and not has_pr:
        # validate-plan never passed: there is no plan PR to hand over
        text = ("⛔ stuck on the plan before a plan PR was opened (it never passed `validate-plan`).\n\n"
                "Clarify the issue if needed, then add the `agent` label again to start over.")
    elif task == "plan":
        text = (head + "\n\nReview this PR as usual: **approve** to start the implementation, or **request "
                "changes** for the planner.")
    elif ctx.state.get("pr"):
        text = (head + f"\n\nSay what to do in a comment here (or push a fix to `{ref}`), then add the `resume` "
                f"label to issue #{n}: the developer carries on from this branch and reads this PR.")
    else:
        # no task PR yet: the issue, not the (merged) PR this run started from
        if n != "?":
            target = int(n)
        text = (head + f"\n\nThe task has no PR yet; its work so far is on `{ref}`. Say what to do in a comment "
                f"here (or push a fix to `{ref}`), then add the `resume` label to issue #{n}: the developer carries "
                "on from that branch.")
    post_comment(ctx, "workflow", text, target=target)
    ctx.gh.add_labels(target, layout.LABEL_HUMAN)
    if task == "plan" and has_pr:
        try:
            ctx.gh.pr_ready(target)
        except GhError:
            pass
        ctx.gh.add_labels(target, layout.LABEL_PLAN)


# ---------------------------------------------------------------- centurion-pr

def classify_review(stage, state, has_text):
    """What the latest human review on a stage:plan / stage:final PR asks for."""
    if state == "APPROVED":
        return "approve-plan" if stage == "plan" else "skip"
    if state in ("CHANGES_REQUESTED", "COMMENTED"):
        return f"changes-{stage}" if has_text else "skip"
    return "skip"


@step("review-gate", start=True)
def review_gate(ctx, args):
    """centurion-pr start. Prints one word: approve-plan | changes-plan | changes-final | resume |
    skip, and keeps the review in human-review.md for whoever acts on it."""
    if ctx.env.get("CEZ_GITHUB_EVENT", "").startswith("issue."):
        n = int(ctx.need_env("CEZ_GITHUB_NUMBER", "no issue"))
        ctx.gh.remove_label(n, layout.LABEL_RESUME)
        ctx.gh.remove_label(n, layout.LABEL_HUMAN)
        feature = layout.FEATURE.format(n=n)
        if not ctx.remote_has(feature):
            warn(f"no {feature} to resume: add the agent label to start from the issue")
            ctx.say("skip")
            return
        ctx.state.update(issue=n, feature=feature)
        ctx.state.drop("pr", "head_ref")
        final = ctx.gh.open_pr(feature)
        if final:
            ctx.state.update(final_pr=final)
        ctx.say(f"resume issue #{n}", "resume")
        return

    pr = int(ctx.need_env("CEZ_GITHUB_NUMBER", "centurion-pr starts from a pull request"))
    ctx.state.update(pr=pr, head_ref=ctx.need_env("CEZ_PR_HEAD_REF", "centurion-pr needs the PR head checkout"))
    labels = {lbl["name"] for lbl in ctx.gh.pr(pr).get("labels", [])}
    if layout.LABEL_PLAN in labels:
        stage, feature = "plan", ctx.env.get("CEZ_PR_BASE_REF", "")
    elif layout.LABEL_FINAL in labels:
        stage, feature = "final", ctx.env["CEZ_PR_HEAD_REF"]
    else:
        ctx.say("skip")
        return
    ctx.state.update(feature=feature, issue=int(feature.removeprefix("feature/issue-")))
    reviews = [r for r in ctx.gh.reviews(pr) if r.get("state") != "PENDING"]
    if not reviews:
        ctx.say("skip")
        return
    last = reviews[-1]
    # Only people with a say in the repository drive the workflow.
    if last.get("author_association") not in ("OWNER", "MEMBER", "COLLABORATOR"):
        ctx.say("skip")
        return
    user = last["user"]["login"]
    ctx.state.update(reviewer=user)
    body = (ctx.gh.review(pr, last["id"]).get("body") or "").strip()
    inline = []
    for c in ctx.gh.review_comments(pr, last["id"]):
        line = c.get("line") or c.get("original_line") or "file"
        inline.append(f"- `{c['path']}:{line}`: {c['body']}")
    text = f"Review by @{user} ({last['state']}):\n\n"
    if body:
        text += body + "\n\n"
    if inline:
        text += "Inline comments:\n" + "\n".join(inline) + "\n"
    ctx.write("human-review.md", text)
    ctx.say(classify_review(stage, last["state"], bool(body or inline)))


@step("start-impl")
def start_impl(ctx, args):
    """The plan was approved: merge the plan PR into the feature branch; the task loop takes over."""
    ctx.state.update(task_id="plan")
    feature = ctx.state["feature"]
    post_comment(ctx, "workflow", f"▶️ Plan approved by @{ctx.state['reviewer']}. Merging it into `{feature}`; "
                 "every task follows as its own PR into that branch.")
    merge_pr(ctx, ctx.target(), "merge")
    delete_branch(ctx, ctx.state["head_ref"])
    ctx.state.drop("pr", "head_ref")
    ctx.say(f"merged plan PR into {feature}")


@step("add-review-task")
def add_review_task(ctx, args):
    """A human reviewed the final PR: append the review as task R<n> to the plan on the feature branch."""
    files = ctx.plan_tasks_files()
    if not files:
        raise StepError(f"no plan ({layout.TASKS_GLOB}) on this branch")
    tasks = files[0]
    reviewer = ctx.state["reviewer"]
    text, task_id = plan.append_review_task((ctx.root / tasks).read_text(), reviewer, ctx.read("human-review.md"))
    (ctx.root / tasks).write_text(text)
    ctx.git("add", tasks)
    ctx.git("commit", "-q", "-m", f"{task_id}: review by @{reviewer}")
    ctx.push(ctx.state["feature"])
    ctx.state.update(final_pr=ctx.state["pr"])
    ctx.state.drop("pr", "head_ref")
    ctx.say(f"added {task_id} to {tasks}")


# ---- keeping the feature branch in step with the main branch

def unmerged(ctx):
    return [f for f in ctx.git("diff", "--name-only", "--diff-filter=U").splitlines() if f]


@step("sync-main")
def sync_main(ctx, args):
    """Merge the main branch into the feature branch (before every task and the final PR). Prints
    `up-to-date`, `merged` (clean; validated and pushed by the next steps) or `conflict` (the merge
    is left in progress for an agent; conflicts.md says what each side did)."""
    feature = ctx.state["feature"]
    main = ctx.main_branch()
    ctx.state.update(task_id="sync", rounds=0)
    ctx.state.drop("pr", "head_ref", "sync_conflicts")
    if not ctx.fetch(feature):
        raise StepError(f"origin has no {feature}")
    ctx.fetch(main)
    ctx.git("reset", "-q", "--hard", f"origin/{feature}")
    if ctx.git_ok("merge-base", "--is-ancestor", f"origin/{main}", "HEAD"):
        ctx.say(f"{feature} has everything from {main}", "up-to-date")
        return
    behind = ctx.gitq("rev-list", "--count", f"HEAD..origin/{main}")
    p = subprocess.run(["git", "merge", "--no-edit", "-m", f"Merge {main} into {feature}", f"origin/{main}"],
                       cwd=ctx.root, capture_output=True, text=True, env=ctx.env)
    if p.returncode == 0:
        ctx.say(f"merged {behind} new commit(s) of {main} into {feature} without conflicts", "merged")
        return
    files = unmerged(ctx)
    if not files:
        raise StepError(f"merging {main} into {feature} failed:\n{p.stdout}{p.stderr}")
    ctx.state.update(sync_conflicts=files)
    mb = ctx.gitq("merge-base", "HEAD", f"origin/{main}")
    doc = [f"# Merge conflict: `{main}` into `{feature}`", "",
           f"`git merge origin/{main}` on `{feature}` stopped with conflicts in:", ""]
    doc += [f"- `{f}`" for f in files]
    doc += ["", f"The branches split at {mb[:12]}. What each side did to these files since then:", ""]
    for f in files:
        doc += [f"## `{f}`", "", f"On `{main}` (already merged there, keep it working):", "```"]
        doc += ctx.git("log", "--oneline", f"{mb}..origin/{main}", "--", f).splitlines() or ["(nothing)"]
        doc += ["```", "", f"On `{feature}`:", "```"]
        doc += ctx.git("log", "--oneline", f"{mb}..HEAD", "--", f).splitlines() or ["(nothing)"]
        doc += ["```", "", f"Both changes: `git diff {mb[:12]} origin/{main} -- {f}` and `git diff {mb[:12]} HEAD -- {f}`.", ""]
    ctx.write("conflicts.md", "\n".join(doc))
    ctx.say(f"merging {main} into {feature} conflicts in:", *("- " + f for f in files), "conflict")


def run_validation(ctx):
    cfg_path = ctx.root / layout.AGENTIC_CONFIG
    commands = json.loads(cfg_path.read_text())["validation"]["commands"] if cfg_path.exists() else []
    for cmd in commands:
        ctx.say(f"$ {cmd}")
        ctx.out.flush()
        p = subprocess.run(["bash", "-c", cmd], cwd=ctx.root, env=ctx.env, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True)
        if p.stdout:
            ctx.out.write(p.stdout if p.stdout.endswith("\n") else p.stdout + "\n")
            ctx.out.flush()
        if p.returncode:
            return p.returncode
    return 0


@step("sync-check")
def sync_check(ctx, args):
    """After merging the main branch: no unresolved conflicts or conflict markers, and the
    validation commands pass."""
    problems = [f"unresolved: {f}" for f in unmerged(ctx)]
    marker = re.compile(r"^(<<<<<<<|>>>>>>>)( |$)|^=======$")
    for f in ctx.state.get("sync_conflicts") or []:
        p = ctx.root / f
        if p.is_file():
            for i, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
                if marker.match(line):
                    problems.append(f"conflict marker: {f}:{i}")
    if problems:
        ctx.say(*problems, f"Resolve them (see {layout.STATE}/conflicts.md).")
        return 1
    return run_validation(ctx)


@step("sync-push")
def sync_push(ctx, args):
    """Conclude the merge of the main branch (if still open) and push it to the feature branch."""
    if ctx.git_ok("rev-parse", "-q", "--verify", "MERGE_HEAD"):
        ctx.git("add", "-A")
        ctx.git("commit", "-q", "--no-edit")
    ctx.push(ctx.state["feature"])
    ctx.state.drop("sync_conflicts")
    ctx.say(f"pushed the merge of {ctx.main_branch()} to {ctx.state['feature']}")


# ---- the task loop

@step("next-task")
def next_task(ctx, args):
    """Start the next task: move to the tip of the feature branch, pick its first open task and
    reset the per-task state. Prints "<id>: <title>", or NONE when every task is done."""
    feature = ctx.state["feature"]
    ctx.fetch(feature)
    ctx.git("reset", "-q", "--hard", f"origin/{feature}")
    tasks = next((f for f in ctx.plan_tasks_files() if plan.has_open_task((ctx.root / f).read_text())), None)
    if not tasks:
        ctx.say("NONE")
        return
    task_id, title, body = plan.first_open_task((ctx.root / tasks).read_text())
    ref = layout.TASK_BRANCH.format(n=ctx.state["issue"], task=task_id.lower())
    base = ctx.head()
    ctx.state.update(tasks_file=tasks, task_id=task_id, task_title=f"{task_id}: {title}", task_body=body,
                     head_ref=ref, base=base, rounds=0)
    ctx.state.drop("pr")
    ctx.remove("review.md", "reply.md", "answer.md")
    doc = [f"# Current task: {task_id}", "",
           f"- Spec: `{plan.spec_for(tasks)}`",
           f"- Full task list: `{tasks}` (tasks marked [x] are done; do not start later ones)",
           f"- The task's change so far: `{layout.CMD} task-diff` (`git diff {base[:12]}`)", "", body.rstrip("\n")]
    note = ""
    # An earlier attempt at this task (escalated, or its run died) left its branch: carry on from it.
    if ctx.fetch(ref):
        tip = f"origin/{ref}"
        resumed = False
        if ctx.git_ok("merge-base", "--is-ancestor", "HEAD", tip):
            ctx.git("reset", "-q", "--hard", tip)
            resumed = True
        else:
            # the feature branch moved on (the main branch was merged in): bring the attempt along
            ctx.git("reset", "-q", "--hard", tip)
            if ctx.git_ok("merge", "-q", "--no-edit", "-m", f"Merge {feature} into {ref}", f"origin/{feature}"):
                resumed = True
                note = f" (merged {feature} into it)"
            else:
                ctx.git("merge", "--abort", check=False)
                ctx.git("reset", "-q", "--hard", base)
                warn(f"the earlier attempt on {ref} does not merge with {feature}: starting over")
        if resumed:
            pr = ctx.gh.open_pr(ref)
            doc += ["", "## Resumed", "",
                    f"An earlier attempt at this task is already in the work tree (`{layout.CMD} task-diff`)."]
            if pr:
                doc += [f"Its PR #{pr} has the exchange so far, including any human comments: `gh pr view {pr} --comments`.",
                        "Finish the task from there; do not start over."]
                ctx.gh.remove_label(pr, layout.LABEL_HUMAN)
            ctx.write("current-task.md", "\n".join(doc) + "\n")
            ctx.say(f"{task_id}: {title} (resumed from {ref}{note})")
            return
    ctx.write("current-task.md", "\n".join(doc) + "\n")
    ctx.say(f"{task_id}: {title}")


@step("task-diff", "[git diff options]", tool=True)
def task_diff(ctx, args):
    """Show the current task's change (`git diff <task base>`)."""
    ctx.out.write(ctx.git("diff", *args, ctx.state["base"]))


@step("verify")
def verify(ctx, args):
    """Run the repository's validation commands (.ai/agentic.config.json), in order; stop at the first failure."""
    return run_validation(ctx)


@step("task-pr")
def task_pr(ctx, args):
    """The task's first green version: push it and open (or reuse) the task PR into the feature branch."""
    ref, feature, n = ctx.state["head_ref"], ctx.state["feature"], ctx.state["issue"]
    ctx.push(ref, force=True)
    pr = ctx.gh.open_pr(ref)
    if not pr:
        body = (f"Task of #{n}, implemented and reviewed by agents (cezar `centurion-pr`). Merged into `{feature}` "
                f"when the reviewer approves.\n\n" + ctx.state["task_body"])
        pr = ctx.gh.create_pr(ref, feature, ctx.state["task_title"], body)
    ctx.state.update(pr=pr)
    ctx.say(f"PR #{pr}: {ref} -> {feature}")


@step("task-reply")
def task_reply(ctx, args):
    """Push the developer's fixes, post the answer to the review and any new screenshots."""
    push_work(ctx)
    post_comment(ctx, "developer", state_file(ctx, "reply.md").read_text())
    return screens.publish(ctx, "developer", optional=True)


@step("mark-done")
def mark_done(ctx, args):
    """The reviewer approved: tick the task, squash its commits, merge the task PR into the feature branch."""
    task_id, tasks = ctx.state["task_id"], ctx.state["tasks_file"]
    path = ctx.root / tasks
    path.write_text(plan.tick(path.read_text(), task_id))
    ctx.git("reset", "-q", "--soft", ctx.state["base"])
    ctx.git("add", "-A")
    ctx.git("commit", "-q", "-m", ctx.state["task_title"])
    ctx.push(ctx.state["head_ref"], force=True)
    # A review task (R<n>) owes the human reviewer an answer per point, on the final PR they reviewed.
    answer = ctx.read("answer.md", "")
    if answer.strip():
        post_comment(ctx, "developer", answer)
        if ctx.state.get("final_pr"):
            post_comment(ctx, "developer", answer, target=ctx.state["final_pr"])
    post_comment(ctx, "workflow", f"✅ approved after {ctx.state.get('rounds') or 0} round(s) of changes; "
                 f"merging into `{ctx.state['feature']}`.")
    merge_pr(ctx, ctx.target(), "squash", ctx.head())
    delete_branch(ctx, ctx.state["head_ref"])
    ctx.say(f"{task_id} merged")


@step("impl-ready")
def impl_ready(ctx, args):
    """Every task is merged: open (or reuse) the final PR into the main branch and hand it to a human."""
    feature, n, main = ctx.state["feature"], ctx.state["issue"], ctx.main_branch()
    issue = None
    pr = ctx.gh.open_pr(feature, main)
    if not pr:
        issue = ctx.gh.issue(n)
        body = (f"Everything for #{n}: the plan and one squashed commit per task, each reviewed by agents in its own "
                f"PR into `{feature}`.\n\nCloses #{n}\n")
        pr = ctx.gh.create_pr(feature, main, issue["title"], body)
    ctx.state.update(pr=pr, task_id="final")
    ctx.gh.add_labels(pr, layout.LABEL_FINAL)
    reviewer = ctx.state.get("reviewer")
    if not reviewer:  # resumed runs have no review: ask the issue's author
        reviewer = (issue or ctx.gh.issue(n))["user"]["login"]
    post_comment(ctx, "workflow", f"✅ All tasks are merged into `{feature}`. Ready for your review, @{reviewer}.\n\n"
                 "- **Approve** and merge when happy.\n"
                 f"- **Request changes** or **comment**: your review becomes a new task with its own PR into `{feature}`.\n")
    try:
        ctx.gh.request_review(pr, reviewer)
    except GhError:
        pass
    ctx.say(f"final PR #{pr}")


@step("plan-answered")
def plan_answered(ctx, args):
    """The planner revised the plan after a human review: push, answer, ask for another look."""
    ctx.state.update(task_id="plan")
    push_work(ctx)
    answer = ctx.read("answer.md", "")
    if not answer.strip():
        answer = "Revised the plan; see the latest commits."
    post_comment(ctx, "planner", answer)
    try:
        ctx.gh.request_review(ctx.target(), ctx.state["reviewer"])
    except GhError:
        pass


# ---------------------------------------------------------------- centurion-cleanup

@step("cleanup", start=True)
def cleanup(ctx, args):
    """An issue's work is over (final PR merged or closed, or the plan PR closed unmerged): close
    the PRs into its feature branch and delete every branch of the issue."""
    pr = int(ctx.need_env("CEZ_GITHUB_NUMBER", "centurion-cleanup starts from a pull request"))
    info = ctx.gh.pr(pr)
    state = "MERGED" if info.get("merged") or info.get("merged_at") else info["state"].upper()
    head = info["head"]["ref"]
    labels = {lbl["name"] for lbl in info.get("labels", [])}
    if layout.LABEL_FINAL in labels:
        n = head.removeprefix("feature/issue-")
    elif layout.LABEL_PLAN in labels:
        if state == "MERGED":  # merging the plan PR is how implementation starts
            ctx.say("plan PR merged: nothing to clean")
            return
        m = re.fullmatch(r"centurion/issue-(.+)-plan", head)
        n = m.group(1) if m else ""
    else:
        ctx.say("not a centurion PR: nothing to clean")
        return
    if state == "OPEN":
        ctx.say(f"PR #{pr} is open: nothing to clean")
        return
    if not n.isdigit():
        raise StepError(f"cannot tell the issue from branch {head}")
    n = int(n)
    ctx.state.update(issue=n, task_id="cleanup")
    feature = layout.FEATURE.format(n=n)
    for other in ctx.gh.open_prs_into(feature):
        ctx.gh.close_pr(other, f"Issue #{n} is done (#{pr} {state.lower()}); closing.")
        ctx.say(f"closed PR #{other}")
    mine = {feature, layout.MOCKUPS_BRANCH.format(n=n), layout.SCREENS_BRANCH.format(n=n)}
    task_prefix = layout.TASK_BRANCH.format(n=n, task="")
    deleted = []
    for line in ctx.git("ls-remote", "--heads", "origin").splitlines():
        branch = line.split("\t", 1)[1].removeprefix("refs/heads/")
        if branch in mine or branch.startswith(task_prefix):
            if delete_branch(ctx, branch):
                deleted.append(branch)
                ctx.say(f"deleted {branch}")
    if deleted:
        post_comment(ctx, "workflow", f"PR #{pr} {state.lower()}: deleted the branches of this issue: "
                     + " ".join(f"`{b}`" for b in deleted), target=n)
    ctx.say(f"issue #{n}: {len(deleted)} branch(es) deleted")

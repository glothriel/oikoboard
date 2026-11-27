"""GitHub through the `gh` CLI (REST via `gh api`, which also works with a gh wrapper that mints
app tokens). The runner is injectable: tests pass an in-process fake that sees the same argv."""

import json
import subprocess
from urllib.parse import quote, urlencode


class GhError(Exception):
    def __init__(self, args, code, stderr):
        super().__init__(f"gh {' '.join(args)}: exit {code}: {stderr.strip()}")
        self.code = code
        self.stderr = stderr


def gh_cli(env=None):
    def run(args, input=None):
        p = subprocess.run(["gh", *args], input=input, capture_output=True, text=True, env=env)
        return p.returncode, p.stdout, p.stderr
    return run


class GitHub:
    def __init__(self, repo, run):
        self.repo = repo
        self.run = run

    # ---- plumbing
    def call(self, args, input=None):
        code, out, err = self.run(list(args), input)
        if code:
            raise GhError(args, code, err)
        return out

    def api(self, path, method="GET", fields=(), typed=(), input=None):
        args = ["api"]
        if method != "GET":
            args += ["-X", method]
        args.append(path)
        for k, v in fields:
            args += ["-f", f"{k}={v}"]
        for k, v in typed:
            args += ["-F", f"{k}={v}"]
        out = self.call(args, input)
        return json.loads(out) if out.strip() else None

    def r(self, rest=""):
        return f"repos/{self.repo}{rest}"

    def paged(self, path):
        sep = "&" if "?" in path else "?"
        items, page = [], 1
        while True:
            chunk = self.api(f"{path}{sep}per_page=100&page={page}") or []
            items += chunk
            if len(chunk) < 100:
                return items
            page += 1

    # ---- issues and comments
    def issue(self, n):
        return self.api(self.r(f"/issues/{n}"))

    def issue_comments(self, n):
        return self.paged(self.r(f"/issues/{n}/comments"))

    def comment(self, n, body):
        self.api(self.r(f"/issues/{n}/comments"), "POST", typed=[("body", "@-")], input=body)

    def add_labels(self, n, *labels):
        self.api(self.r(f"/issues/{n}/labels"), "POST", fields=[("labels[]", label) for label in labels])

    def remove_label(self, n, label):
        """Remove a label; False when it was not there (or the call failed)."""
        try:
            self.api(self.r(f"/issues/{n}/labels/{quote(label, safe='')}"), "DELETE")
            return True
        except GhError:
            return False

    # ---- pull requests
    def pr(self, n):
        return self.api(self.r(f"/pulls/{n}"))

    def pr_state(self, n):
        p = self.pr(n)
        if p.get("merged") or p.get("merged_at"):
            return "MERGED"
        return p["state"].upper()

    def open_pr(self, head, base=None):
        """The number of the open PR from branch `head` (into `base`), or None."""
        q = {"state": "open", "head": f"{self.repo.split('/')[0]}:{head}"}
        if base:
            q["base"] = base
        prs = self.api(self.r("/pulls?" + urlencode(q))) or []
        return prs[0]["number"] if prs else None

    def open_prs_into(self, base):
        return [p["number"] for p in self.paged(self.r("/pulls?" + urlencode({"state": "open", "base": base})))]

    def create_pr(self, head, base, title, body, draft=False):
        p = self.api(self.r("/pulls"), "POST", fields=[("title", title), ("head", head), ("base", base)],
                     typed=[("body", "@-"), ("draft", "true" if draft else "false")], input=body)
        return p["number"]

    def pr_ready(self, n):
        self.call(["pr", "ready", str(n), "-R", self.repo])

    def close_pr(self, n, comment):
        self.comment(n, comment)
        self.api(self.r(f"/pulls/{n}"), "PATCH", fields=[("state", "closed")])

    def request_review(self, n, user):
        self.api(self.r(f"/pulls/{n}/requested_reviewers"), "POST", fields=[("reviewers[]", user)])

    def merge(self, n, method, sha=None):
        fields = [("merge_method", method)] + ([("sha", sha)] if sha else [])
        self.api(self.r(f"/pulls/{n}/merge"), "PUT", fields=fields)

    def reviews(self, n):
        return self.api(self.r(f"/pulls/{n}/reviews?per_page=100")) or []

    def review(self, n, review_id):
        return self.api(self.r(f"/pulls/{n}/reviews/{review_id}"))

    def review_comments(self, n, review_id):
        return self.api(self.r(f"/pulls/{n}/reviews/{review_id}/comments?per_page=100")) or []

    def delete_branch(self, branch):
        self.api(self.r(f"/git/refs/heads/{branch}"), "DELETE")

# Intent (cezar em-plan, first step)

Before any spec, settle what the issue author wants. This is the human's only say before the plan PR,
so it is short and about the product. The author is technical and may also say how it should be
built: keep those hints (their opinion, which the plan follows unless the code makes it wrong).

Read the issue with its comments (`.ai/cezar/em/state/issue.md`), `AGENTS.md` and enough of the app to
know what exists today. Then write `.ai/cezar/em/state/intent.md`, at most ~20 lines:

```markdown
**Want:** <what changes for whom, and why; one to three sentences>
**Where:** <screens / API / jobs it touches, by name>
**In scope:** <bullets>
**Not in scope:** <bullets>
**Author's implementation hints:** <bullets, as the author put them; omit if none>
**Assumptions:** <bullets: every choice the issue does not make that you would make>
```

## Questions

Ask (in `.ai/cezar/em/state/questions.md`, numbered) whenever the issue leaves a product choice open:

- two reasonable readings of the issue lead to a different feature;
- something users see or do is not specified and no existing pattern in the app decides it
  (where it lives, what happens on edge cases users will hit, defaults, who may do it);
- scope: whether a related thing is part of this or not.

Do not ask about implementation the author left open (data model, libraries, file layout): the plan
decides those and the human reviews them on the plan PR. Do ask when an implementation hint of the
author is unclear or clashes with the code as it is. At most five questions, each with the answer
you propose, so the human can reply "1-4 ok, 5: ...". A previous round of questions and the answers
are in the issue comments: do not ask again what is answered.

No open questions: verdict `clear`. Otherwise verdict `questions`; the workflow posts the intent with the
questions on the issue and stops until the human answers and adds the `agent` label again.

---
name: council
description: Trigger this if the user says 'council'.
---

# Council

Before an audit, address outstanding PR comments, fix known issues, and run
relevant checks. Give council the updated implementation; do not defer known
fixes until reviews return. If the user wants to discard the implementation
and explore new ideas, skip fixes to code being replaced.

Bring in three delegates to help with the user's request, usually for review
or feedback. Use the model you are running on for all three, at high reasoning
effort. If the user's instructions name a model, use that. Give each delegate
a different lens so the same model does not return the same review three
times: correctness, scope and simplicity, and risk and proof. For feedback that
is not a code review, pick distinct lenses that fit the request.

In T3 Code, use `orchestrator_capabilities` to resolve the model, then
`delegate_task` to start one delegate per lens in parallel. Elsewhere, use
the harness's subagent tools. If the model is unavailable, report it
instead of substituting.

Give each delegate the request, its lens, and relevant context. For review or feedback,
keep their work read-only. Collect their responses and summarize the useful
findings, disagreements, and recommended next steps.

For a code review, ask each delegate for a score out of 10.
Count each full review pass as one round.
A fresh review after fixes starts a new round.

If the work ends in a pull request, put the results in the PR description.
Put this section before the model and harness line at the end:

```markdown
## Council review

Rounds: 2

| Delegate | Round 1 | Round 2 |
| --- | --- | --- |
| Correctness | 7/10 | 9/10 |
| Scope and simplicity | 8/10 | 10/10 |
| Risk and proof | 7/10 | 9/10 |
```

If a delegate gives no score, write `no score`. Do not invent one.
If the PR is open, edit the description. Do not post a comment for this.
If there is no PR, put the same results in the final reply only.

If you agree with their recommendations, make the changes and request a fresh
review after. Continue this process until all delegates are satisfied with the
outcome.

Do not let repeated reviews result in scope creep. It is your job to fight to
keep scope limited.

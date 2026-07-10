---
name: codex-gated-development
description: Use when starting any non-trivial engineering implementation task or a quant strategy backtest in this project — applies from the moment a concrete task or strategy idea arrives, before any planning or coding begins.
---

# Codex-Gated Development

## Overview

A development pipeline where **no artifact advances to the next phase until an independent Codex adversarial review has signed off**, and — for quant work — **the backtest code is reviewed before it is ever run**.

**Core principle:** External review is a *gate*, not a formality. You converge each review loop by triaging findings — fix the valid ones, rebut the invalid ones with technical reasoning — never by blindly implementing everything, and never by declaring "good enough" because the reviewer is annoying or you are out of time.

**Two modes, one principle:**
- **Engineering** — plan → gate → implement → gate.
- **Quant backtest** — study → playbook + code → **gate → run**.

The gate is the same in both: `/codex:adversarial-review` (challenges approach/design) or `/codex:review` (code review of git state). Both are review-only — they print Codex's findings and change nothing. You do the triage and the fixing.

## When to Use

- Starting a concrete engineering task (feature, refactor, bugfix) beyond a trivial one-liner.
- Starting a quant strategy backtest — from a strategy idea through to a validated verdict.

**When NOT to use:** genuinely trivial edits (a typo, a comment, a pure prose/doc edit) with no logic and no bug surface. Everything with a branch, a loop, a fill/sizing/cost path, or a look-ahead risk goes through the gates. A change to ANY value or operator on a cost, slippage, risk-sizing, stop/target, fill, signal-timing / bar-indexing / next-bar-offset / look-ahead, session-timezone, aggressor-polarity, or data-selection path is NEVER trivial — this includes numeric constants, comparison / min / max / sign operators, rolling-window / shift() and next-bar / entry-bar index offsets (`shift(1)`→`shift(2)`, `i+1`→`i`), field references (high/low/open/close), and string-valued config (timezone, contract/cost preset, cache-column selector, side field). It has little or no logic but maximal bug surface, and always goes through the gates. A "string edit" is trivial only when it is pure prose — never when the string is a config value, path, timezone, preset, or column selector. If in doubt whether an edit is trivial, it is not: gate it.

## The Gate (shared by every review loop)

Codex reviews **git working-tree / branch state**, so an artifact must exist as a file for Codex to see it. Untracked files count.

**The gate must review a non-empty diff that actually contains your artifact's logic.** Before accepting a pass, confirm the reviewed diff contains the artifact's *actual substance* — the fill / sizing / stop / look-ahead / signal lines — not just the filename or a docstring/comment/whitespace hunk. A diff that merely touches the file while the real logic sits in an earlier commit is a SKIPPED gate (partial-commit / decoy-hunk defeats a presence-only check). A review that reports "nothing to review" or lists no findings on an empty diff is likewise a SKIPPED gate, not a clean pass. If ANY part of the artifact has ever been committed for this task (check `git log --oneline -- <file>`), you MUST review with an explicit base that predates this task so the full artifact is in the diff: `/codex:adversarial-review --base <commit-before-this-task>` (or review before committing). Reviewing the working tree (default `--scope auto` on a **dirty** tree) shows only the uncommitted hunks and will miss committed logic. Never rely on default `--scope auto` when the working tree is clean, and never accept a working-tree/auto review of a file that has committed history for this task.

```
LOOP, per gate:
  1. WRITE the artifact to a file in the repo (plan / spec / playbook), or ensure the code diff exists.
  2. RUN the Codex review command, pointing its focus text at the artifact.
  3. TRIAGE every finding with /receiving-code-review:
       - valid & correct for THIS codebase  → fix it (revise the plan / fix the code)
       - wrong / YAGNI / doesn't apply here  → rebut with technical reasoning; record it; do NOT implement
       - ambiguous, or conflicts with a decision the user already made → escalate to the user
  4. RE-RUN the Codex review.
  5. STOP only after a Codex RE-RUN on the CURRENT artifact state surfaced no
     valid-and-unaddressed finding (only already-rebutted points remain, or nothing).
     You may NEVER stop on an iteration in which you edited the artifact without re-running:
     the pass that clears the gate must have seen your final fixes, since a fix can
     introduce the very look-ahead / sizing / next-bar-fill bug the gate exists to catch.
     The gate-clearing re-run must be the LAST operation that mutates the artifact before
     it ships. If you touch the artifact AFTER a clearing pass — for ANY reason, including
     a "trivial" rename / comment / constant — the gate re-opens: re-run Codex on that
     state before stopping. The trivial-edit carve-out never applies to a change layered
     on top of an already-cleared artifact.
```

**Convergence discipline — the part that is easy to get wrong:**
- "No new comments" means **no new *valid* finding** — not "Codex went silent," and not "I'm tired of this loop."
- You do **not** get to label a finding invalid just to end the loop. A rebuttal must be technical reasoning that survives the user reading it. Correctness / look-ahead / sizing / concurrency findings are **presumed valid until you have checked the code** and shown otherwise.
- You do **not** blindly implement every finding either — that never converges and breaks working code. That is why step 3 triages.
- **Bound the loop by finding class, not by patience.** Split findings into **blocking** (correctness, look-ahead, sizing, spec-violation, security — the classes presumed-valid above) and **residual** (style, "you could also", speculative hardening). The gate clears when a fresh re-run shows **no blocking finding** — residuals are logged, not chased. An adversarial reviewer can always emit one more "consider X"; chasing residuals to a literally-empty report is the non-convergence trap, not diligence. "Residual" may **never** absorb a correctness / look-ahead / sizing finding — those are blocking by definition.
- **Convergence must be monotone — otherwise escalate, don't spin.** Each round must shrink the blocking set. If a round surfaces a blocking finding your own prior fix introduced (oscillation), or the blocking set is not shrinking after ~3 rounds, STOP looping and **escalate to the human** with the current state and findings — a review that won't converge means the plan/design is wrong, not that it needs another round. This is the ONLY early exit, and it hands off to a person; it is never a licence to silently ship an unconverged gate. A loop that IS shrinking just runs to zero blocking findings — the cap fires only on genuine non-convergence.
- The gate is `/codex:review` or `/codex:adversarial-review` (review-only). `codex:rescue` delegates/fixes — it is **not** the gate.

## Engineering Mode

| Phase | Do this | Gate |
|-------|---------|------|
| 1. Plan | `/brainstorming` (if intent/requirements aren't already crisp) → produce a spec/design; then a plan. Write it to a file. | — |
| 2. **Gate #1** | `/codex:adversarial-review` the spec + plan (focus text → the file). Run the loop above. | ✅ before any code |
| 3. Impl plan | `/writing-plans` → detailed task-by-task implementation plan. Write to a file. | — |
| 4. **Gate #2** | `/codex:adversarial-review` the implementation plan. Run the loop. | ✅ before any code |
| 5. Implement | `/subagent-driven-development` (fresh implementer per task + per-task spec/quality review; it recommends an isolated worktree). | — |
| 6. Self-verify | `/verification-before-completion` — run the module self-checks / tests, confirm green with real output. | — |
| 7. Clean up | `/simplify`, then `/code-review`. Triage & address findings (`/receiving-code-review`). | — |
| 8. **Gate #3** | `/codex:review` (or `/codex:adversarial-review`) on the final diff. Run the loop. | ✅ before done |
| 9. Finish | `/finishing-a-development-branch`. | — |

**Small-task collapse (observable predicate):** if the task is small enough that the spec and the implementation plan are one document, run **one** planning gate on that document instead of Gate #1 and Gate #2 separately. Either way: **at least one Codex gate clears before any implementation code is written.**

## Quant Backtest Mode

| Phase | Do this | Gate |
|-------|---------|------|
| 1. Study first | Characterize the raw phenomenon in a throwaway study (base rates, forward-return distribution/asymmetry) before building anything. It may ONLY characterize the raw phenomenon — it may **not** simulate the strategy, apply entries/stops/targets, or compute strategy P&L / R-multiples / t-stats; producing any strategy-return number here is running the backtest before the gate. Any signal-timing / fill / aggressor-sign / session-tz logic the study shares with backtest.py is gated in Phase 4 exactly as if written there — a passing study result never pre-clears it and is never admissible as a Phase-4 rebuttal. If the base rate is uninteresting, **stop** — don't build a harness around a non-event. | — |
| 2. Playbook | Write `strategies/<name>/playbook.md`: thesis, **exact** rules (what counts as the signal, entry on next-bar open per no-look-ahead, stop, target/exit), parameters, universe. Results/verdict are TBD. This is the spec. | — |
| 3. Backtest code | Write `strategies/<name>/backtest.py` on `strategies/common/harness.py` — inherits realistic `CostModel`, fixed 0.5%-risk sizing, 10× cap, R-multiple/t-stat metrics. Analyze on NQ, execute on MNQ. | — |
| 4. **Gate (mandatory, BEFORE running)** | `/codex:adversarial-review` the playbook **+** backtest.py together. Point the reviewer at the bug classes that manufacture fake edges: look-ahead / next-bar-fill violations, inverted aggressor polarity, wrong session timezone, degraded-day handling, sizing/cost errors, and whether the code faithfully implements the playbook's stated rules. Run the loop. | ✅ **before the first real run** |
| 5. Run | Only after sign-off: run the actual backtest. | — |
| 6. Read skeptically | Full-sample net P&L, t-stat of R-multiples, and **per-year**. Holds only if consistent across years **AND** t > 2. | — |
| 7. Robustness | Param plateau (not a spike), cost sensitivity (micro cost? 2× slippage?), pre/post-2024 OOS split. | — |
| 8. Verdict | Write the honest verdict into the playbook — including "not robust" when that's what the numbers say. | — |

**Why review the code before running it:** a look-ahead / inverted-fill / wrong-timezone / sizing bug *silently manufactures a fake edge*. If you run first and see an exciting t-stat, you are now biased to defend the bug. Review the code cold — before any result exists to fall in love with.

## Rationalizations — STOP if you catch one

| Excuse | Reality |
|--------|---------|
| "It's a small / one-liner change (a constant bump), skip the gates" | Small diffs hide the subtlest bugs — that is exactly where a fill/sizing/off-by-one error lives. A one-literal change to a cost/slippage/risk/stop constant has no logic but maximal bug surface. The gate is cheap. Run it. |
| "I fixed/rebutted everything this round, so I already know a re-run would be clean — skip it" | Your fixes are unreviewed until Codex sees them; a fix can add the very look-ahead/sizing bug the gate exists to catch. The gate clears only on a pass that ran against the state you're shipping — never on your prediction of that pass. |
| "The gate already cleared; this last cleanup is too trivial to re-gate" | A post-gate edit is unreviewed code shipping through a gate that never saw it — the trivial-edit exemption only covers standalone edits with no gate in play, never a mutation layered on top of a cleared artifact. Re-run, or don't make the edit. |
| "Let me run the backtest first just to see if the idea has legs, review the code after" | A look-ahead / inverted-fill / tz bug manufactures a fake edge. Once you've seen a good t-stat you'll defend the bug. Review before the first run — always. |
| "The throwaway study already showed the edge / base rate, so the backtest just confirms it" | The study is un-gated and can carry the exact look-ahead / inverted-fill / tz bug that manufactures the number — a result you saw before the gate is precisely what you must not fall in love with. The Phase-4 gate must clear on backtest.py's own logic, cold; study output is not evidence and not a rebuttal. |
| "Codex always finds *something*, a clean pass is impossible, I'll stop" | The loop ends when no *valid, unaddressed* finding remains — not when Codex goes silent. Triage each finding first; stopping before triage is skipping the gate. |
| "The reviewer keeps surfacing new things — I'll loop until the report is literally empty" | An adversarial reviewer never runs out of "consider X". Gate on the *blocking* class clearing (correctness / look-ahead / sizing / spec) and log residuals — don't chase an empty report. If the blocking set isn't shrinking after ~3 rounds, the design is wrong: escalate to a person, don't spin — and never silently ship an unconverged gate. |
| "This finding is just a nitpick" | Then say why, in writing, as a technical rebuttal — don't wave it away. Correctness / look-ahead / sizing findings are presumed valid until you've checked the code. |
| "I'll implement every Codex comment to be safe" | Blind implementation never converges and breaks working code. Triage: fix valid, push back on wrong-for-this-codebase. |
| "I already self-reviewed / the per-task reviewer passed — the final Codex gate is redundant" | Self-review and per-task review live inside your own context. The Codex gate is the independent adversary. Both are required. |
| "The plan is obvious, I'll just start coding" | The obvious plan is where the wrong assumption hides. At least one planning gate clears before any code. |
| "Time pressure ('today') — I'll compress the process" | Compressing drops the gates that catch the expensive bug. The pipeline IS the fast path; a shipped bug costs more than the gate. |

## Red Flags — STOP and run the gate you skipped

- About to write implementation code and **no Codex gate has cleared the plan** yet.
- About to **run the actual backtest** and Codex hasn't reviewed the backtest code yet.
- About to call the work done **without** `/simplify` + `/code-review` + a final Codex gate.
- Implementing a Codex finding **without** evaluating whether it's correct for this codebase.
- Declaring the review loop "done" because Codex is annoying or you're out of time — **not** because findings are triaged.
- Reaching for `codex:rescue` as the review gate — the gate is `/codex:review` or `/codex:adversarial-review`.

## Quick Reference

- Planning gate → `/codex:adversarial-review` (challenges approach/design).
- Final code gate → `/codex:review` or `/codex:adversarial-review`.
- Triage findings → `/receiving-code-review` (verify before implementing; rebut with reasoning).
- Implement → `/subagent-driven-development`.
- Verify → `/verification-before-completion`.
- Clean up → `/simplify` then `/code-review`.
- Codex is review-only and reads git state → write plans/specs/playbooks to files first.

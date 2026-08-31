# Architecture

Read the documents in numbered order:

1. [System overview](01-overview.md) — reciprocal review gates, shared
   engineering skills, and their ownership and external-review boundaries.

## Authoring standard

Architecture is a compact, present-tense model of the current core design, not
an implementation reference or change log. It explains durable module
boundaries, primary control and data flows, ownership and lifecycles, durable or
wire formats, external integrations, system-level correctness, safety, and
compatibility invariants, and the stable rationale needed to understand those
choices.

Maintenance is claim-driven. For an implementation change, identify the
current architectural claim or core model that would otherwise become false or
materially incomplete. Update architecture when such a claim exists; leave it
unchanged when the change is local to an implementation. Initial bootstrap and
dedicated documentation work may establish the model, correct an inaccuracy,
fill a core-design gap, or consolidate existing sediment without an
implementation trigger.

Write at the highest useful level of abstraction and preserve rationale for a
stable constraint or tradeoff. Revise or replace related prose so the resulting
document stands on its own without the commit that produced it. Prefer one
coherent current explanation over appended before-and-after narratives.

Use the narrowest durable home for each kind of information:

| Information | Home in this repository |
|---|---|
| Core responsibility, ownership, lifecycle, cross-module flow, external integration, durable contract, system-level invariant, or stable rationale | `docs/architecture/` |
| Significant historical decision, alternatives, superseded design, or architectural evolution | `docs/plans/` or `docs/superpowers/` |
| Supported installation or operating procedure and its prerequisites | `README.md` or the relevant user-facing guide |
| Local algorithm, runtime representation, tuning mechanism, or code-level invariant | Nearby skill, script, or API documentation |
| Change motivation, before/after behavior, change-specific benchmark result, or implementation journey | Pull request or commit |

Treat this routing as exclusionary. Omit information assigned to a narrower
home instead of retaining it as a negative disclaimer or inventory of
implementation details. Record an absent capability only when that absence
defines a current system boundary, supported behavior, or system-level
invariant.

Keep claims evidence-grounded. Every architecture document ends with a
`Source map` that connects its claims to concrete repository-relative files or
directories and labels any unknowns explicitly.

For example, changing which runtime owns a review gate or moving ownership of
general Codex review away from the external `code-review` skill changes the
core model and belongs here
(`claude/skills/codex-gated-development/`,
`codex/skills/claude-gated-development/`). Changing a wrapper's exact lock or
checkpoint representation belongs near that script unless it changes the
gate-level concurrency or review-continuity contract. Changing how
`bootstrap-project` owns managed blocks or selects the authoritative
architecture hierarchy belongs here; a helper's temporary-file mechanics do
not (`shared/skills/bootstrap-project/`).

## Source map

| Claim | Repository source |
|---|---|
| Review gates, shared skills, ownership, and external-review boundaries | `docs/architecture/01-overview.md` |
| Architecture authoring and placement contract | `shared/skills/bootstrap-project/SKILL.md`; `shared/skills/bootstrap-project/assets/project-instructions.md` |

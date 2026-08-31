---
name: bootstrap-project
description: Use when initializing AI engineering infrastructure in a new repository or bringing an existing repository's instructions, architecture docs, and pull request template up to a shared baseline.
---

# Bootstrap Project

Build the smallest evidence-grounded baseline while preserving repository-specific instructions and documentation structure.

## Required sequence

1. Read every applicable instruction file, including existing `AGENTS.md` and `CLAUDE.md`, and inventory existing documentation before editing anything. Read `docs/README.md` when present, then read the repository's existing documentation entry point, architecture index, and relevant current-architecture documents before choosing taxonomy or drafting prose.
2. Read the root README and inspect manifests, source and test roots, build/test entry points, runtime entry points, persistence, and external integrations. Scan the source tree and sample implementation and tests around apparent boundaries, excluding vendored, generated, cache, and worktree directories. Record an evidence-backed module map before drafting architecture prose. A durable module has an independent responsibility plus a meaningful interface, data flow, or lifecycle; paths alone are not evidence. For every durable module, capture its responsibility, evidence paths, and architecture-document destination.
3. Use the module map to choose the documentation taxonomy. In the default `docs/architecture/` hierarchy, keep `01-overview.md` at system level and use focused numbered subsystem documents; in an existing equivalent hierarchy, preserve its paths, overview, and naming and navigation conventions. A repository with at most one durable module may keep readable architecture detail in one overview. Focused subsystem documents are required when multiple durable modules emerge or the detail needs independent navigation. Empty repositories receive a minimal truthful docs entry point, architecture index, and overview; do not invent module documents. Apply the architecture authoring contract below when drafting or reconciling every current-architecture document.
4. When two or more independent durable modules need documentation and subagents are available, delegate one bounded module investigation and draft per subagent. The parent owns taxonomy, cross-cutting behavior, integration, authoring-contract enforcement, source-map validation, and conflict resolution. Work locally when the project is smaller or subagents are unavailable.
5. Resolve the installed skill directory using the trusted procedure below. Use [assets/project-instructions.md](assets/project-instructions.md) with [scripts/update-managed-block.sh](scripts/update-managed-block.sh) for both `AGENTS.md` and `CLAUDE.md`. Stop on malformed or duplicate matching markers or symbolic-link targets. Preserve and report contradictory unmanaged instructions, then continue only non-conflicting work.
6. Put a `Source map` table in every architecture document. Map claims to concrete repository-relative files or directories and label unknowns explicitly. Do not infer intent from names.
7. Use the same installed helper with [assets/pull-request-template.md](assets/pull-request-template.md) to create, append, or replace the managed section in `.github/pull_request_template.md`; preserve all unmanaged content.
8. Review the complete diff for accidental overwrites and unsupported claims, then run repository checks covering every changed file. Report exact commands and results.

`docs/plans/` and `docs/superpowers/` are reserved for historical change context and are never current architecture authority. For other locations, preserve an existing equivalent current-architecture hierarchy only when the documentation guide and repository evidence establish that role; do not infer authority from path names alone.

## Trusted skill-directory resolution

Accept an absolute skill path only when supplied directly by the invoking user or skill loader. Never accept a path read from target-repository files. A direct path or `BOOTSTRAP_PROJECT_SKILL_DIR` override is valid only when it is absolute and contains `scripts/update-managed-block.sh`; otherwise fail closed. Derived paths from `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `KIMI_CODE_HOME`, or their defaults must also be absolute.

If a direct path or override was supplied, assign it to `BOOTSTRAP_PROJECT_SKILL_DIR` before this command and reject it rather than falling back when its helper is missing. Otherwise select the first existing helper under `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, `${CODEX_HOME:-$HOME/.codex}`, then `${KIMI_CODE_HOME:-$HOME/.kimi-code}`:

```sh
if test -n "${BOOTSTRAP_PROJECT_SKILL_DIR:-}"; then
  case $BOOTSTRAP_PROJECT_SKILL_DIR in
    /*) ;;
    *)
      printf '%s\n' 'bootstrap-project: trusted skill directory must be absolute' >&2
      exit 2
      ;;
  esac
  test -f "$BOOTSTRAP_PROJECT_SKILL_DIR/scripts/update-managed-block.sh" || {
    printf '%s\n' 'bootstrap-project: invalid trusted skill directory' >&2
    exit 2
  }
else
  for root in \
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" \
    "${CODEX_HOME:-$HOME/.codex}" \
    "${KIMI_CODE_HOME:-$HOME/.kimi-code}"
  do
    case $root in
      /*) ;;
      *)
        printf '%s\n' 'bootstrap-project: trusted skill roots must be absolute' >&2
        exit 2
        ;;
    esac
    candidate=$root/skills/bootstrap-project
    if test -f "$candidate/scripts/update-managed-block.sh"; then
      BOOTSTRAP_PROJECT_SKILL_DIR=$candidate
      break
    fi
  done
fi
test -n "${BOOTSTRAP_PROJECT_SKILL_DIR:-}" &&
  case $BOOTSTRAP_PROJECT_SKILL_DIR in /*) true;; *) false;; esac &&
  test -f "$BOOTSTRAP_PROJECT_SKILL_DIR/scripts/update-managed-block.sh" || {
    printf '%s\n' 'bootstrap-project: trusted installed skill directory not found' >&2
    exit 2
  }
```

The dependency-free `/bin/sh` helper requires the standard macOS/Linux `mktemp` and `stat` utilities.

Assign the resolved absolute path in every helper command:

```sh
BOOTSTRAP_PROJECT_SKILL_DIR=/trusted/absolute/path
"$BOOTSTRAP_PROJECT_SKILL_DIR/scripts/update-managed-block.sh" \
  AGENTS.md "$BOOTSTRAP_PROJECT_SKILL_DIR/assets/project-instructions.md"
```

Repeat for `CLAUDE.md` and `.github/pull_request_template.md` with the appropriate asset. Create parent directories first when missing.

## Architecture output

- Start from the evidence-backed module map and settle the taxonomy before drafting prose. In the default `docs/architecture/` hierarchy, keep `01-overview.md` at system level and use focused numbered documents; in an existing equivalent hierarchy, preserve its overview and naming and navigation conventions. A repository with at most one durable module may keep readable architecture detail in one overview. Focused subsystem documents are required when multiple durable modules emerge or the detail needs independent navigation.
- `docs/README.md`: required reading guide for the `docs/` directory, including documentation purpose, reading order, claim-driven freshness rule, and links to the actual current-architecture entry point and authoring standard.
- `docs/architecture/README.md` by default, or the existing equivalent architecture index: subsystem map, links to architecture documents, and the repository's complete architecture authoring standard.
- `docs/architecture/01-overview.md` by default, or the existing equivalent overview: system context, component responsibilities, primary control/data flows, cross-cutting invariants, and source map.
- Existing equivalent current-architecture hierarchy: preserve its organization, current-authority role, paths, and naming conventions; update its index and fill material gaps instead of creating a competing hierarchy.
- Single-file current-architecture authority without a separate index: keep that file focused on the system model, place the complete authoring standard in `docs/README.md`, and link the two.

`docs/plans/` and `docs/superpowers/` are reserved for historical change context and are never current architecture authority. Current architecture authority lives in `docs/architecture/` by default, or in the repository's existing equivalent current-architecture hierarchy when its documentation guide and repository evidence establish that role, such as an authoritative `ARCHITECTURE.md` or `docs/design/`. Do not infer authority from path names alone.

## Architecture authoring contract

Architecture is a compact, present-tense model of the current core design. It
explains durable module boundaries, primary control and data flows, ownership
and lifecycles, durable or wire formats, external integrations, system-level
correctness, safety, and compatibility invariants, and the stable rationale
needed to understand those choices. Local implementation details and release
history live in their narrower homes.

Architecture maintenance is claim-driven. For an implementation change,
identify the existing claim or core model that would otherwise become false or
materially incomplete. Update architecture when the change crosses one of the
boundaries above; leave it unchanged when no such claim exists. Initial
bootstrap and dedicated documentation work may establish the model, correct an
inaccuracy, fill a core-design gap, or consolidate existing sediment without an
implementation trigger.

Write the resulting design at the highest useful level of abstraction. Preserve
rationale for a stable constraint or tradeoff. Revise or replace related prose
so the document stands on its own without the originating commit; prefer one
coherent current explanation over appended change narratives.

Use the narrowest durable home for each kind of information:

| Information | Home |
|---|---|
| Core responsibility, ownership, lifecycle, cross-module flow, durable or wire contract, system-level invariant, and stable rationale | Current-architecture hierarchy |
| Significant historical decision, alternatives, superseded design, or architectural evolution | Repository's historical design or plan area |
| Supported operational procedure, prerequisite, or safety boundary | Operations documentation |
| Local algorithm, runtime representation, tuning mechanism, or code-level invariant | Nearby source or API documentation |
| Change motivation, before/after behavior, change-specific benchmark result, and implementation journey | Pull request or commit |

Treat this routing as exclusionary. Omit information assigned to a narrower
home instead of retaining it in architecture as a negative disclaimer or an
inventory of implementation details. Record an absent capability only when
that absence defines a current system boundary, supported behavior, or
system-level invariant.

Reconcile this contract with any existing authoring guidance in the actual
architecture index, adapting documentation locations and short examples to
repository evidence rather than adding a second standard. When a single
authoritative architecture file has no separate index, put the reconciled
contract in `docs/README.md` instead so that file stays focused on the system
model. In both cases, `docs/README.md` must point readers to the standard and
current-architecture entry point. A durable format compatibility change belongs
in architecture, while an exact in-memory layout or local optimization
mechanism belongs near its implementation.

A `Source map` table uses claims, not guesses:

| Claim | Repository source |
|---|---|
| Service runtime entry | `src/service/main.*` |
| Persistence boundary | `Unknown; confirm before documenting` |

Replace examples with paths observed in the target repository.

## Quick reference

| Output | Source or rule | Merge behavior |
|---|---|---|
| `AGENTS.md`, `CLAUDE.md` | `assets/project-instructions.md` | Create, append, or replace one matching managed block |
| Architecture docs | Repository evidence and the authoring contract | Reconcile current claims and taxonomy; preserve equivalent existing content |
| `.github/pull_request_template.md` | `assets/pull-request-template.md` | Create, append, or replace one matching managed block |
| Validation | Repository checks | Record exact commands and results |

## RED-phase counters

| Pressure response observed without this skill | Required response |
|---|---|
| Update only `AGENTS.md` because time is short | Complete both instruction files, the architecture set with source maps, and the PR template. |
| Treat architecture as obvious and skip documentation | Inspect actual boundaries and cite repository-relative paths; label unknowns. |
| Append a change note because implementation changed | Apply the current-claim test. If an update is required, revise the present-tense model and keep the change narrative in the PR or commit. |
| “No comments needed; code is self-explanatory” | Keep that judgment for syntax-restating comments. Add only comments or public API docs required by the managed engineering standards. |

Do not defer documentation or comment work to PR preparation.

# Codex gate: persistent review sessions, risk routing, optional Kimi

Date: 2026-07-25. Status at authoring time: plan for review, before implementation.

## Problem

The Claude Code gate (`claude/skills/codex-gated-development/`) still runs every
Codex review through the `openai-codex` plugin commands `/codex:review` and
`/codex:adversarial-review`. Both start a fresh ephemeral Codex thread per
invocation (`review/start` and `runAppServerTurn` with `ephemeral: true`), so a
multi-round gate loop re-reads the entire task scope on every round. The mirror
Codex-side gate (`codex/skills/claude-gated-development/`) already solved this:
one persistent reviewer session per (repository, task key), full first review,
incremental `--since` rounds after committed fixes. The plugin is
marketplace-managed and cannot be patched locally without being overwritten,
and its native reviewer has no resume API at all.

Two policy gaps also diverge from the newer mirror skill:

- The Claude-side gate is size-triggered ("any non-trivial task"), not
  risk-routed. The mirror routes by concrete risk and skips external review for
  local, reversible, single-path work.
- The Claude side has no optional Kimi specialist second opinion; the mirror
  supports `--kimi-risk` for concurrency/idempotency/transaction/tenant/
  distributed-state risks.

## Approach

Bypass the plugin for the gate. Add a repo-owned runner that drives the Codex
CLI headlessly with persistent sessions, and rewrite the Claude-side skill to
be risk-routed with Codex as the sole mandatory external gate and Kimi as an
optional, never-blocking specialist.

Verified CLI capabilities (codex-cli 0.144.4, on this machine):

- `codex exec resume <SESSION_ID> [PROMPT]` resumes a persisted session
  headlessly; sessions live under `~/.codex/sessions`.
- `codex exec --json` emits JSONL events; `thread.started` carries `thread_id`.
- Parent flags (`--json`, `--sandbox`, `--output-last-message`, `-c`) must
  precede the `resume` subcommand; `resume` rejects them when placed after it.
- `--sandbox read-only` gives an OS-level read-only reviewer shell.
- `-c 'mcp_servers={}'` does NOT clear configured MCP servers — TOML table
  overrides merge per key (`codex -c 'mcp_servers={}' mcp list` still shows the
  user's servers), and plugin-provided MCP servers plus stable `hooks`,
  `plugins`, and `apps` features load outside `mcp_servers` anyway. Reviewer
  isolation therefore layers:
  - `--ignore-user-config --ignore-rules` for the user layer, plus explicit
    `--disable hooks --disable plugins --disable apps` (feature names verified
    in `codex features list` on 0.144.4), keeping `-c 'mcp_servers={}'` only
    as a redundant guard;
  - a neutral working root: the runner invokes `codex exec` from an empty
    directory under the run's tmpdir with `--skip-git-repo-check`, so
    project-layer configuration (`.codex/config.toml` in the reviewed
    repository — reviewed content must never configure its own reviewer) can
    never load regardless of the repository's trust state. Verified on
    0.144.4 that an untrusted project's `.codex/config.toml` MCP table is not
    loaded even from inside the project; the neutral root removes the trusted
    case too. Absolute paths in the prompt and bundle keep the repository
    readable through the read-only sandbox.
  - Managed/system configuration layers (MDM, cloud-managed config) are the
    machine operator's policy; the runner does not and should not try to
    bypass them.
- `CLAUDE_CODE_SESSION_ID` is exported to Bash by Claude Code and serves as the
  default per-conversation session key (mirror of `CODEX_THREAD_ID` on the
  Codex side).

Precedent: `kimi/skills/kimi-gated-development/scripts/codex-review.sh` already
implements the codex exec mechanics (thread-id capture, resume fallback,
flag-ordering constraint, `--ephemeral` keyless mode). The newest wrapper
architecture (incremental checkpoints, verdict contract, optional sandboxed
Kimi) lives in `codex/skills/claude-gated-development/scripts/claude-review.sh`.
The new runner merges the two.

## Deliverables

### 1. `claude/skills/codex-gated-development/scripts/codex-review.sh`

Bash runner, same interface as the mirror:

```
codex-review.sh adversarial|code [--base REF] [--since REF] [--focus TEXT]
                [--kimi-risk RISK]... [--session-key KEY]
```

- Scope semantics identical to `claude-review.sh`: working tree without
  `--base`; `REF...HEAD` plus working tree with `--base`; committed delta only
  with `--base` + `--since` on a clean tree with a verified checkpoint,
  ancestry-validated, failing closed to a full review on any mismatch.
- Review bundles: same `full-review-scope.txt` / `incremental-review-scope.txt`
  construction (branch diff, status, staged/unstaged diffs, untracked list;
  incremental patch plus full-task stat/name-status summary).
- Codex invocation: from a neutral empty working root under the run tmpdir,
  `codex exec --ignore-user-config --ignore-rules --disable hooks
  --disable plugins --disable apps -c 'mcp_servers={}' --skip-git-repo-check
  --json --sandbox read-only --output-last-message <file>` with the prompt as
  the positional argument and stdin pinned to `/dev/null`. Resume rounds insert
  `resume <session-id>` after the shared parent flags. Keyless runs add
  `--ephemeral` and persist nothing. Authentication is unaffected
  (`auth.json` is separate from `config.toml`, and sessions under
  `$CODEX_HOME/sessions` resume independently of the working root); the
  reviewer runs on Codex defaults rather than user profiles, which is
  intended.
- Session state: `<git-common-dir>/codex-review-sessions/<hash>` where
  `<hash> = git hash-object("<repo_root>\0<session_key>")`, mode 0600 via
  `umask 077`. Key resolution: `--session-key` >
  `CODEX_REVIEW_SESSION_KEY` > `CLAUDE_CODE_SESSION_ID`. Checkpoints per mode
  in `<hash>.<mode>.reviewed` holding `base_oid head_oid session_id`, written
  only after a valid verdict on a clean tree with `--base`.
- Serialization and identity binding (hardening beyond the mirror):
  - A per-key lock (`mkdir <session-file>.lock`, removed on exit) serializes
    all rounds sharing a key; a held lock fails the invocation loudly instead
    of interleaving turns or corrupting state.
  - A checkpoint is honored only when its recorded `session_id` matches the
    current session file, in addition to the mirror's base-equality and
    ancestry checks; any mismatch or malformed checkpoint falls back to a full
    review. This prevents pairing a checkpoint with a Codex session that never
    reviewed the checkpointed scope (e.g. after a resume-failure replacement).
  - The default key scopes the reviewer to one Claude conversation. The
    SKILL's command templates always pass an explicit per-task
    `--session-key <task-key>`, and the SKILL states the rule directly:
    distinct tasks use distinct keys, sequential or concurrent, and a fresh
    key always starts with a full first review. The env-derived default
    remains only as a fallback for ad-hoc manual runs. Within a key, rounds
    are serial by contract and by lock. Incremental soundness never depends
    on this convention: a checkpoint is honored only when the resumed session
    itself produced it (session-id binding) for the same task base, so the
    session has reviewed `base..checkpoint-head` in-context and the reviewed
    union stays complete even if an operator reuses a key across tasks.
- First keyed round runs a new session and captures `thread_id` from the
  `thread.started` event. A keyed round that cannot capture or save the id
  fails the gate (exit 5) rather than silently degrading persistence. A failed
  resume falls back to a new full-scope session (an incremental patch alone is
  not interpretable in a fresh conversation), then persists the new id.
- Reviewer prompt: the mirror's review-only contract adapted to a shell-based
  reviewer: read-only sandbox notice; read the precomputed bundle first, then
  inspect CLAUDE.md/AGENTS.md guidance and named files; scope-substance check;
  blocking vs residual findings; machine-readable final line
  `VERDICT: PASS | NEEDS REVISION | SKIPPED`. Recursion block is prompt-level:
  do not invoke any gated-development skill, the review wrapper scripts, or
  another external reviewer CLI (`claude`, `kimi`); the read-only sandbox and
  the isolated run configuration (no user config, rules, hooks, plugins, apps,
  or MCP servers) enforce non-mutation and no tool escalation.
- Verdict validation: same `has_review_verdict` last-verdict-wins parsing; a
  successful process with no valid `PASS`/`NEEDS REVISION` line fails the gate;
  empty final message fails the gate.
- Repository fingerprint guard before/after the review (HEAD, porcelain status,
  diffs, untracked hashes and modes) — any change fails the gate (exit 4).
- Optional Kimi specialist review: ported from `claude-review.sh` —
  `--kimi-risk` whitelist (concurrency, idempotency, database-transactions,
  tenant-isolation, distributed-state), detached snapshot workspace, native
  sandbox (macOS `sandbox-exec` deny-subpath profile; Linux Bubblewrap tmpfs
  masks with private PID namespace and `/proc`), empty skills dir, fresh full
  snapshot per round, concurrent with the Codex review, warnings-only on any
  Kimi failure; a missing sandbox or setup failure downgrades to Codex-only.
- Bounded Kimi wait (hardening beyond the mirror, which waits unconditionally
  and can hang the gate): the runner waits for the mandatory Codex review
  without a deadline, then grants the still-running Kimi process a bounded
  grace period (`KIMI_REVIEW_GRACE_SECONDS`, default 300) polled once per
  second. On expiry it terminates the Kimi process group (`set -m` gives the
  background pipeline its own process group; TERM, then KILL after a short
  pause), reports the timeout as a warning, and completes normally — verdict
  printed, checkpoint advanced, lock released. A hung optional reviewer can
  therefore never block the mandatory gate.
- Kimi tool confinement (hardening beyond the mirror): the runner generates a
  reviewer agent definition and passes `--agent-file`, with frontmatter
  `tools: ["Read", "Grep", "Glob"]` — an allowlist, so a naming drift fails
  closed by removing tools from an already non-blocking reviewer rather than
  leaving dangerous ones reachable. On Kimi 0.29.0, `--agent-file` in prompt
  mode requires the v2 engine, enabled via `KIMI_CODE_EXPERIMENTAL_FLAG=1` in
  the reviewer environment (verified: without the flag the CLI hard-errors
  `--agent/--agent-file are only available with the v2 engine`, with it the
  agent file is read); the runner sets that flag for the Kimi process, and the
  hard error rather than silent ignoring means a future Kimi that drops the
  flag fails visibly instead of running unrestricted. Kimi agent definitions
  parse both `tools` and `disallowedTools` (verified in the installed binary),
  and the builtin registry includes `Write`, `Edit`, `Bash`, `WebSearch`,
  `FetchURL`, `Agent`, and `AgentSwarm`, none of which remain available to
  the reviewer.
  This removes unattended write, shell, network-fetch, and subagent-delegation
  surfaces from prompt-mode `auto` permission policy; the reviewer prompt's
  subagent allowance is dropped on this side accordingly. Implementation
  includes a one-time functional verification against the real CLI that the
  agent profile actually restricts the tool surface, and README records the
  tested Kimi version contract. The native sandbox remains the second layer
  for live-repository integrity, and both gate skills state the explicit
  trusted-repository precondition (the user already runs this repository's
  code directly) instead of silently assuming it.

### 2. `claude/skills/codex-gated-development/SKILL.md` rewrite

Mirror the structure and policy of `codex/skills/claude-gated-development/
SKILL.md` with the reviewer roles swapped:

- Core policy: route by concrete risk, not diff size; skip external review for
  local, reversible, single-path work with an obvious implementation and a
  direct check. Codex is the sole mandatory external gate; Kimi is an optional
  specialist second opinion that never blocks the Codex gate but whose valid
  findings must still be triaged.
- Triggers: cross-module/integration boundaries, ambiguous architecture,
  concurrency, security, destructive data, financial or quant logic including
  real backtests, durable interfaces (schemas, protocols, migrations,
  persistence formats), hard-to-verify failure modes. Risk triggers override
  artifact type: operative Markdown — skill definitions, reviewer prompts,
  policy documents, agent configuration — is gated like code when a trigger
  applies, because in repositories like this one prose IS the runtime surface.
  Diff size alone never triggers; tiny changes on financial paths (cost,
  slippage, sizing, fills, signal timing, offsets, look-ahead, timezone,
  polarity, data selection, rolling windows) remain gated. The prose exemption
  is limited to non-operative documentation: typos, comments, and prose that
  no runtime or reviewer behavior depends on.
- Commands section pointing at the runner:
  `RUNNER="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/codex-gated-development/scripts/codex-review.sh"`
  with `adversarial` planning gate, `code` final gate, `--base`, `--since`,
  `--kimi-risk` examples, session continuity keyed by `CLAUDE_CODE_SESSION_ID`
  or `--session-key`.
- Keep: scope-integrity rules (untracked files count, committed history needs
  `--base`, empty/partial/SKIPPED targets fail), the triage/convergence
  discipline (blocking vs residual, monotone convergence, escalation),
  engineering and quant workflows, rationalization table, quick reference with
  `finish-pr` then `/finishing-a-development-branch`, Claude-side helper skills
  (`/brainstorming`, `/writing-plans`, `/receiving-code-review`,
  `/subagent-driven-development`, `/verification-before-completion`,
  `/simplify`, `/code-review`).
- Frontmatter description updated to the risk-routed trigger so the skill fires
  on risk, not on "any non-trivial task".

### 3. Tests

- New `claude/skills/codex-gated-development/scripts/test-codex-review-session.sh`
  with a fake `codex` binary: persist/resume per (repo, key); resume flag
  ordering (parent flags before `resume`, `--sandbox` after `resume` is an
  error); read-only sandbox, `--json`, `--ignore-user-config`,
  `--ignore-rules`, `--skip-git-repo-check`, and the hooks/plugins/apps
  feature disables on every reviewer run; the fake records its working
  directory and the test asserts it is a neutral root outside the repository;
  no `--ephemeral` on keyed runs; `--ephemeral` and no resume on keyless
  runs; stale-session fallback replaces and persists a new session;
  distinct keys and repositories do not share sessions; hashed 0600 state
  files that cannot escape the state dir; state-write and id-capture failures
  fail keyed gates; a held per-key lock fails a second invocation and a stale
  lock is not silently removed; stdin pinned; empty final message and
  missing/SKIPPED-only verdicts fail; fingerprint mutation fails; incremental
  bundle contains the new patch body, omits old patch bodies, includes the
  full-task summary; checkpoint recording includes the session id, and a
  checkpoint whose session id does not match the stored session forces a full
  review, as does a malformed checkpoint; the fail-closed incremental
  rejections (`--since` without `--base`, empty range, non-ancestor history,
  dirty tree); fresh-fallback rounds send the full task; Kimi risk whitelist,
  Kimi non-blocking failures, Kimi snapshot isolation from the live repo; the
  fake `kimi` asserts it received `--agent-file` whose frontmatter allowlists
  exactly `Read`, `Grep`, and `Glob`, and that
  `KIMI_CODE_EXPERIMENTAL_FLAG=1` is present in its environment; a hanging
  fake `kimi` (long sleep) with a short `KIMI_REVIEW_GRACE_SECONDS` proves the
  runner still prints the Codex verdict, advances the checkpoint, terminates
  the Kimi process group, warns about the timeout, and releases the per-key
  lock for the next round.
- One-time real-CLI smoke verification during implementation (not in the
  hermetic suite): a restricted-profile `kimi -p` review completes and reports
  a tool surface without write/shell/network tools, and the dogfood Codex run
  doubles as the MCP-absence check via its `--json` event stream.
- `tests/test-engineering-infrastructure.sh`: replace the `| 9. Finish |`
  table-row assertion with assertions matching the rewritten SKILL (runner
  path, `sole mandatory external gate`, Kimi non-blocking sentence,
  `--kimi-risk concurrency`, `--since <previous-reviewed-head>`, finish
  handoff line) plus runner-content assertions mirroring the existing
  `CODEX_GATE_RUNNER` checks (recursion prohibition, verdict contract line).

### 4. Documentation

- `README.md`: describe both routed gates symmetrically (risk routing,
  persistent reviewer session per task, `--since` incremental rounds, optional
  Kimi specialist on both sides), and document the Claude-side gate's runtime
  prerequisites: an installed and authenticated `codex` CLI (tested with
  codex-cli 0.144.4; requires `codex exec resume` and JSONL `thread.started`
  events), reviewer sessions stored under `${CODEX_HOME:-~/.codex}/sessions`,
  fail-closed behavior when the CLI is missing or incompatible, the optional
  Kimi version contract (tested with Kimi 0.29.0 agent-file tool allowlists),
  the trusted-repository precondition for running reviewers against a
  repository at all, and the fact that the `openai-codex` plugin is no longer
  required for the gate (rescue and stop-hook flows keep using the plugin
  independently).
- `docs/architecture/01-overview.md`: update the Claude Code gate component row
  (risk routing + runner script source), primary flow step 3 (both gates run a
  full first review then verified incremental rounds), invariants (checkpoint
  invariant and reviewer-recursion invariant now cover both wrappers; Codex
  reviewer confinement = read-only sandbox + empty MCP + prompt contract),
  source map (add the new scripts path).
- Plan retained under `docs/plans/` as historical context.

## Non-goals

- No change to `codex/skills/claude-gated-development/` or the Kimi-side
  skill. (Superseded for two defects — see the scope addendum below.)
- No plugin patching; `/codex:rescue` and the stop-review-gate hook keep using
  the plugin runtime. An upstream feature request for review-thread resume is
  worth filing but out of scope.
- No structured-output schema for the reviewer (the mirror uses free text plus
  the VERDICT line; parity is the goal).
- No cross-machine session portability: Codex sessions live in the local
  `~/.codex/sessions`; a new machine or wiped Codex home simply falls back to a
  full fresh review.

## Risks and mitigations

- `codex exec --json` event names could drift in future CLI versions →
  thread-id extraction failure fails keyed gates loudly (exit 5), and the
  keyless path still works; the session test pins the current contract.
- Long-lived reviewer sessions accumulate context → Codex compacts
  automatically; every incremental prompt restates the authoritative bundle
  paths, and any checkpoint doubt falls back to a full review.
- Reviewer could theoretically shell out to another agent CLI → prompt-level
  prohibition plus read-only sandbox (no writes) with user config, rules,
  hooks, plugins, apps, and MCP surfaces disabled for the run; the fingerprint
  guard catches any repository mutation regardless.
- Future Codex versions could rename the disabled feature flags → `--disable`
  of an unknown feature must not silently re-enable the surface; the runner
  treats a failed reviewer start as a failed gate, and the session test pins
  the current flag set.

## Review round 1 triage (2026-07-25)

Adversarial review verdict: needs-attention, five findings.

1. MCP lockdown claim false (high) — confirmed empirically
   (`codex -c 'mcp_servers={}' mcp list` still lists servers; plugin MCP and
   hooks/plugins/apps features load regardless). Fixed: reviewer runs with
   `--ignore-user-config --ignore-rules --disable hooks --disable plugins
   --disable apps`, retaining `-c 'mcp_servers={}'` only as redundancy; tests
   assert the flag set.
2. Session/checkpoint identity and serialization (high) — fixed beyond the
   mirror: per-key `mkdir` lock, session id recorded in checkpoints and
   required to match, SKILL guidance for distinct `--session-key` per
   concurrent task. The conversation-scoped default key itself is retained:
   it mirrors `CODEX_THREAD_ID` semantics on the Codex side, and checkpoint
   base-equality plus session binding already prevent cross-task incremental
   scope loss; a task-derived key cannot be synthesized reliably from inside
   one conversation.
3. Pure-prose exemption bypass (high) — fixed: risk triggers override artifact
   type; operative Markdown is gated; exemption narrowed to non-operative
   documentation.
4. Kimi sandbox does not confine the host (high) — partially adopted. The
   deny-live-repo boundary is the mirror's documented, accepted design; a
   host-allowlist sandbox would break Kimi's own authentication, runtime, and
   network, for an optional advisory reviewer that never gates. Adopted: the
   trusted-repository precondition becomes explicit in SKILL and README.
   Rebutted: rebuilding the sandbox as an allowlist is out of scope and
   parity-breaking; repository-integrity guarantees (snapshot isolation,
   fingerprint, non-blocking role) are unaffected.
5. Missing installation prerequisites (medium) — fixed: README documents the
   mandatory Codex CLI, tested version and capability contract, session
   storage location, fail-closed behavior, and the plugin's remaining role.

## Review round 2 triage (2026-07-25)

Verdict: needs-attention, three findings (blocking set shrank 5 → 3).

1. Non-user config layers can still supply MCP servers (high) — fixed with a
   neutral working root: the reviewer never executes from inside the reviewed
   repository, so project-layer `.codex/config.toml` cannot load even for
   trusted projects (probe confirmed untrusted projects load nothing already);
   `--skip-git-repo-check` added. Managed/system config layers are rebutted as
   out of threat model: they are the machine operator's policy, and a review
   wrapper that bypassed MDM-managed configuration would itself be hostile.
   Full flag-set assertions plus a neutral-cwd assertion go into the session
   test; the real-run dogfood gate doubles as the functional MCP-absence
   check (its `--json` event stream shows any MCP startup).
2. Sequential tasks sharing a conversation key (high) — partially adopted.
   The SKILL's command templates now always pass an explicit per-task
   `--session-key`, with the stated rule that distinct tasks take distinct
   keys and a fresh key forces a full first review. Requiring a task key
   before any `--since` at the runner level is rebutted: incremental
   soundness does not rest on the key convention — a checkpoint is honored
   only when the resumed session itself produced it for the same base, so the
   reviewed union `base..HEAD` is complete even under key reuse; the residual
   effect of reuse is reviewer-context carryover, the same accepted property
   the mirror has with conversation-scoped `CODEX_THREAD_ID`.
3. Kimi is an unattended host-capable agent under `-p` auto policy (high) —
   fixed rather than rebutted this round: the runner now pins the Kimi
   reviewer to an `--agent-file` profile whose `tools` allowlist is exactly
   `Read`, `Grep`, `Glob` (no `Bash`, `Write`, `Edit`, `WebSearch`,
   `FetchURL`, `Agent`, `AgentSwarm`), verified parseable on Kimi 0.29.0 and
   fail-closed by construction; prompt-injection from snapshot content can no
   longer reach write, shell, network-fetch, or delegation tools. Native
   sandbox, non-blocking role, and the now-explicit trusted-repository
   precondition remain as layered context.

## Review round 3 triage (2026-07-25)

Verdict: needs-attention, one finding (blocking set shrank 3 → 1); the
neutral-root and checkpoint/session-key rebuttals were accepted.

1. `--agent-file` requires the v2 engine on Kimi 0.29.0 (medium) — confirmed
   by local probe (hard error without `KIMI_CODE_EXPERIMENTAL_FLAG=1`; with
   the flag the agent file is read). Without the fix every specialist review
   would degrade warnings-only to Codex-only, silently defeating the round-2
   hardening. Fixed: the runner sets `KIMI_CODE_EXPERIMENTAL_FLAG=1` in the
   Kimi environment, the fake-CLI test asserts the flag, and implementation
   adds a one-time real-CLI smoke verification that the restricted profile
   completes a prompt-mode review. The hard-error behavior is retained as the
   desired failure mode: a future Kimi that drops the flag fails visibly and
   non-blockingly rather than running unrestricted.

## Scope addendum (2026-07-25, user decision)

Two defects surfaced by the review rounds were originally deferred as
follow-up tasks; the user folded both into this change:

1. The mirror wrapper's unbounded `wait "$kimi_pid"` (round-4 finding) is
   fixed in `codex/skills/claude-gated-development/scripts/claude-review.sh`
   with the same bounded-grace/process-group design as the new runner, plus a
   hanging-fake-kimi regression case, a SKILL policy sentence covering hangs,
   and updated infrastructure assertions.
2. `codex/skills/claude-gated-development/scripts/test-claude-review-session.sh`
   aborted under macOS system bash 3.2 (`sandbox_prefix[@]: unbound variable`
   with `set -u` on an empty array); the expansion now uses the portable
   `${arr[@]+...}` guard so the suite runs on a stock Mac.

## Dogfood gate round 1 triage (2026-07-25)

The final code gate ran through the new runner itself. The optional Kimi
concurrency review returned PASS after examining the lock, background-job,
grace-timeout, and fingerprint paths (it raised and self-resolved a
zombie-reaping question: bash reaps via its SIGCHLD handler, so the grace
loop exits promptly — matching the hang test's observed timing). The round
itself ended with the fingerprint guard failing the gate because the scope
addendum edits landed while the review was running — the guard doing its
job; round 2 reviews the final state by resuming the same session.

Codex verdict: NEEDS REVISION, one blocking finding.

1. Interrupted runs release the per-key lock without terminating reviewer
   processes (P1) — valid. The EXIT-only cleanup removed the lock and tmpdir
   while backgrounded reviewers could still be alive, so an interrupt could
   leave an orphan sharing the persistent session with the next round —
   exactly the interleaving the lock exists to prevent. Fixed in both
   wrappers: reviewers now launch under job control in their own process
   groups; cleanup terminates and reaps those groups (TERM, then KILL)
   before removing temporary data or the lock; HUP/INT/TERM route through
   the EXIT trap. Interruption regression cases (hang the fake reviewer,
   TERM the wrapper, assert the reviewer died, the lock was released only
   afterwards, and the next round works) cover both suites.

Residual (logged, not chased): non-regular untracked files (e.g. a FIFO)
could stall the snapshot or fingerprint under the trusted-repository
precondition; speculative hardening.

## Review round 4 triage (2026-07-25)

Verdict: needs-attention, one finding. The round-3 fix was accepted; this
round surfaced a defect inherited from the mirror, not an oscillation of a
prior fix.

1. Optional Kimi has no bounded wait (high) — valid: the mirror's
   `wait "$kimi_pid"` is unconditional, so a hung Kimi CLI would block the
   verdict, checkpoint, and per-key lock forever, contradicting
   "never-blocking". Fixed in this runner: unbounded wait applies only to the
   mandatory Codex review; Kimi then gets a bounded grace
   (`KIMI_REVIEW_GRACE_SECONDS`, default 300), after which its process group
   is terminated (TERM then KILL), the timeout is reported as a warning, and
   the run completes with the Codex verdict, advanced checkpoint, and
   released lock. A fake-Kimi hang test with a short grace pins the behavior.
   The same defect in `codex/skills/claude-gated-development/scripts/
   claude-review.sh` is out of scope here and tracked as follow-up work.

## Verification

- `bash claude/skills/codex-gated-development/scripts/test-codex-review-session.sh`
- `bash codex/skills/claude-gated-development/scripts/test-claude-review-session.sh`
- `sh tests/test-engineering-infrastructure.sh`
- Dogfood: clear the final code gate for this change by running the new runner
  itself (`codex-review.sh code` on the full working tree, keyed by the live
  Claude session).

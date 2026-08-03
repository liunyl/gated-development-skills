# gated-development-skills

Gate skills for Claude Code, Codex CLI, and Kimi Code. Both routed gates are
risk-routed rather than size-routed: local, reversible, single-path work with
a direct check skips external review, while concrete complex or high-risk
work uses the opposite runtime's model as the sole mandatory external gate
for planning and final reviews. Risk triggers override artifact type —
operative Markdown (skills, reviewer prompts, policy) gates like code. Real
quant backtests remain gated before their first run.

Each mandatory review mode starts with the full task; after fixes are
committed, later rounds in the same persistent reviewer session can use
`--since <previous-reviewed-head>` to send only the new commit range plus a
full-task summary. On the Claude side the Codex reviewer session is resumed
with `codex exec resume`, checkpoints additionally bind the reviewing session
id, and a per-key lock serializes rounds. Optional Kimi review is limited to
named concurrency, idempotency, transaction, tenant-isolation, and
distributed-state risks; it always sees a fresh full snapshot through a
native sandbox and never blocks the mandatory gate — Kimi quota, transport
failure, or a hang degrades to a warning, and both runners terminate a hung
Kimi after a bounded grace (`KIMI_REVIEW_GRACE_SECONDS`, default 1800). On the
Claude side Kimi additionally runs under an agent profile whose tool
allowlist is exactly `Read`, `Grep`, and `Glob`; on the Codex side it may use
built-in subagents. Kimi may not chain to another external reviewer or
review gate.

Both gates review changes in repositories you already trust enough to build
and run locally; they do not make an untrusted repository safe to work in.

| Skill | Lives in | Purpose |
|-------|----------|---------|
| `codex-gated-development` | Claude Code — `~/.claude/skills/` | Claude side: risk-routed gate; Codex reviews in one persistent session per task (`--session-key`), with optional tool-restricted Kimi specialist review |
| `claude-gated-development` | Codex CLI — `~/.codex/skills/` | Codex side: gate complex/high-risk work with Claude; optionally target Kimi at named state-consistency risks |
| `kimi-gated-development` | Kimi Code — `~/.kimi-code/skills/` | Kimi side: judgment-triggered dual gate — Claude and Codex review in parallel, each reusing one persistent session per task across all review rounds |

The tool-neutral engineering skills install unchanged in every runtime:

| Skill | Trigger |
|-------|---------|
| `bootstrap-project` | Use when a new or existing repository needs shared engineering instructions, an evidence-grounded architecture baseline, and a pull request template. |
| `finish-pr` | Use after implementation, before creating or updating a pull request, to audit the final diff and draft the commit and PR content. |

## Install on a new machine

```bash
git clone git@github.com:liunyl/gated-development-skills.git
cd gated-development-skills

mkdir -p ~/.claude/skills ~/.codex/skills ~/.kimi-code/skills
cp -R claude/skills/codex-gated-development ~/.claude/skills/
cp -R codex/skills/claude-gated-development ~/.codex/skills/
cp -R kimi/skills/kimi-gated-development ~/.kimi-code/skills/

for runtime in .claude .codex .kimi-code; do
  mkdir -p "$HOME/$runtime/skills"
  cp -R shared/skills/bootstrap-project shared/skills/finish-pr "$HOME/$runtime/skills/"
done
```

Optional Kimi reviews use the native sandbox: `sandbox-exec` on macOS or
Bubblewrap on Linux. Ubuntu installs Bubblewrap with:

```bash
sudo apt-get install bubblewrap
```

Ubuntu 24.04 and later may also require the packaged AppArmor profile:

```bash
sudo apt-get install apparmor-profiles
sudo install -m 0644 /usr/share/apparmor/extra-profiles/bwrap-userns-restrict \
  /etc/apparmor.d/bwrap-userns-restrict
sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict
```

That's it — each tool auto-discovers skills under its `skills/` dir.

`codex-gated-development` needs an installed and authenticated `codex` CLI:
the gate drives it headlessly and fails closed when the CLI is missing,
unauthenticated, or incompatible. Tested with codex-cli 0.144.4; the runner
requires `codex exec resume` and the JSONL `thread.started` event for session
capture. Reviewer sessions persist under `${CODEX_HOME:-~/.codex}/sessions`;
wiping them only costs a fresh full first review. The reviewer runs from a
neutral working root with user config, rules, hooks, plugins, apps, and MCP
servers disabled, so no configuration layer of the reviewed repository or
user profile reaches the gate. The `openai-codex` Claude Code plugin is not
required for the gate; rescue and stop-hook flows keep using the plugin
independently. Optional Kimi review needs the `kimi` CLI (tested with Kimi
0.29.0, whose v2 engine honors the runner's read-only agent profile via
`KIMI_CODE_EXPERIMENTAL_FLAG=1`; a Kimi that rejects it degrades to a
warning, never an unrestricted run).

`kimi-gated-development` needs both the `claude` and `codex` CLIs installed
and authenticated; its reviewers are review-only (read-only tool surface /
sandbox) and keep one session per task per reviewer, so later rounds resume
instead of reloading context. It installs to Kimi's private skill dir
(`~/.kimi-code/skills/`), NOT the shared `~/.agents/skills/`: Codex and other
agents scan the shared dir, and they must not adopt a skill whose two
reviewers are themselves.

Comments and architecture documentation are implementation-time work:
`bootstrap-project` installs those expectations in the repository instructions.
`finish-pr` audits the completed change and hands branch lifecycle operations to
the runtime's established finishing workflow instead of duplicating them.

## Install Codex plugin adapters

From the repository root:

```bash
codex plugin marketplace add .
codex plugin add pr-review-toolkit@gated-development-skills
codex plugin add code-simplifier@gated-development-skills
codex plugin add frontend-design@claude-plugins-official
```

Or add the marketplace directly from GitHub:

```bash
codex plugin marketplace add liunyl/gated-development-skills --ref master
```

The first two plugins adapt upstream Claude-only `agents/` and `commands/`
layouts into Codex skills. Frontend Design already contains a Codex-compatible
skill, so install it directly from the official marketplace.

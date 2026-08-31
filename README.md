# gated-development-skills

Reciprocal gate skills for Claude Code and Codex CLI. Both gates are risk-routed
rather than size-routed: local, reversible, single-path work with a direct
check skips external review, while concrete complex or high-risk work always
selects the opposite runtime's model for planning and final reviews. Risk
triggers override artifact type —
operative Markdown (skills, reviewer prompts, policy) gates like code. Real
quant backtests remain gated before their first run.

Each mandatory review mode starts with the full task; after fixes are
committed, later rounds in the same persistent reviewer session can use
`--since <previous-reviewed-head>` to send only the new commit range plus a
full-task summary. On the Claude side the Codex reviewer session is resumed
with `codex exec resume`, checkpoints additionally bind the reviewing session
id, and a per-key lock serializes rounds. Keyless reviews always start full
without reusable continuity.

Both gates review changes in repositories you already trust enough to build
and run locally; they do not make an untrusted repository safe to work in.

| Skill | Lives in | Purpose |
|-------|----------|---------|
| `codex-gated-development` | Claude Code — `~/.claude/skills/` | Claude side: risk-routed Codex gate with one persistent reviewer session per task |
| `claude-gated-development` | Codex CLI — `~/.codex/skills/` | Codex side: risk-routed Claude gate with one persistent reviewer session per task |

The tool-neutral engineering skills install unchanged in every runtime:

| Skill | Trigger |
|-------|---------|
| `bootstrap-project` | Use when a new or existing repository needs shared engineering instructions, an evidence-grounded architecture baseline, and a pull request template. |
| `finish-pr` | Use after implementation, before creating or updating a pull request, to audit the final diff and draft the commit and PR content. |
| `finish-branch` | Use when implementation is complete and tests pass, to choose and execute the branch integration path (merge, PR, keep, or discard). Vendored from Superpowers (MIT). |

## Install on a new machine

```bash
git clone git@github.com:liunyl/gated-development-skills.git
cd gated-development-skills

mkdir -p ~/.claude/skills ~/.codex/skills
cp -R claude/skills/codex-gated-development ~/.claude/skills/
cp -R codex/skills/claude-gated-development ~/.codex/skills/

for runtime in .claude .codex .kimi-code; do
  mkdir -p "$HOME/$runtime/skills"
  cp -R shared/skills/bootstrap-project shared/skills/finish-pr shared/skills/finish-branch "$HOME/$runtime/skills/"
done
```

These repository skills are now discoverable under each tool's `skills/` dir.

Existing installations of the retired Kimi gate are not removed automatically.
After verifying the targets, remove these exact legacy paths:

- `~/.kimi-code/skills/kimi-gated-development/` (or the equivalent under
  `$KIMI_CODE_HOME`).
- `${XDG_DATA_HOME:-$HOME/.local/share}/gated-development-skills/kimi-review.sh`.

The `.kimi-code` entry in the shared-skill loop remains intentional.
Old `--kimi-risk` wrapper invocations now fail as unknown arguments.

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
independently.

Comments are implementation-time work. Architecture documentation is updated
alongside implementation only when that implementation makes a current
architecture claim or core model false or materially incomplete;
`bootstrap-project` installs those expectations in the repository instructions.

`finish-pr` audits the completed change and hands branch lifecycle operations to
the bundled `finish-branch` skill (vendored from Superpowers, MIT) or the
runtime's established finishing workflow instead of duplicating them.

Codex's engineering workflow also requires Matt Pocock's externally managed
`code-review` and setup skills:

```bash
npx skills add mattpocock/skills -g --skill code-review setup-matt-pocock-skills
```

Run `/setup-matt-pocock-skills` once in each repository so
`docs/agents/issue-tracker.md` exists. Update them with
`npx skills update code-review setup-matt-pocock-skills -g`; this repository
intentionally does not vendor or patch those skills.

## Install Codex plugin adapter

Existing installations of the retired reviewer plugin are not removed
automatically. Remove that exact plugin before installing the adapter below:

```bash
codex plugin remove pr-review-toolkit@gated-development-skills
```

From the repository root:

```bash
codex plugin marketplace add .
codex plugin add code-simplifier@gated-development-skills
codex plugin add frontend-design@claude-plugins-official
```

Or add the marketplace directly from GitHub:

```bash
codex plugin marketplace add liunyl/gated-development-skills --ref master
```

The repository plugin adapts the upstream Claude-only `code-simplifier` agent
into a Codex skill. Frontend Design already contains a Codex-compatible skill,
so install it directly from the official marketplace.

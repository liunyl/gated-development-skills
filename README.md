# gated-development-skills

Gate skills for Claude Code, Codex CLI, and Kimi Code. Both routed gates are
risk-routed rather than size-routed: local, reversible, single-path work with
a direct check skips external review, while concrete complex or high-risk
work always selects the opposite runtime's model for planning and final
reviews. Risk triggers override artifact type —
operative Markdown (skills, reviewer prompts, policy) gates like code. Real
quant backtests remain gated before their first run.

Each mandatory review mode starts with the full task; after fixes are
committed, later rounds in the same persistent reviewer session can use
`--since <previous-reviewed-head>` to send only the new commit range plus a
full-task summary. On the Claude side the Codex reviewer session is resumed
with `codex exec resume`, checkpoints additionally bind the reviewing session
id, and a per-key lock serializes rounds. Kimi selection is limited to named
concurrency, idempotency, transaction, tenant-isolation, and distributed-state
risks. Both gates call the same shared Kimi runner, which maintains an explicit
session and verified checkpoint when a task/session key is available, streams
native progress plus heartbeats, and reviews a detached snapshot through a
native sandbox. Keyless reviews always start full without reusable continuity.
The snapshot is scrubbed after every round; only the stable working-directory
shell, isolated Kimi runtime, and small session/checkpoint files persist. Kimi
selection is optional; once selected, failure, `NEEDS REVISION`, invalid
output, or the bounded timeout (`KIMI_REVIEW_TIMEOUT_SECONDS`, default 1800)
blocks the gate. Kimi may use built-in subagents but may not chain to another
external reviewer or review gate. The sandbox makes the host read-only to Kimi
except for its detached workspace and isolated Kimi runtime.

Both gates review changes in repositories you already trust enough to build
and run locally; they do not make an untrusted repository safe to work in.

| Skill | Lives in | Purpose |
|-------|----------|---------|
| `codex-gated-development` | Claude Code — `~/.claude/skills/` | Claude side: risk-routed Codex gate with conditionally mandatory Kimi specialist review |
| `claude-gated-development` | Codex CLI — `~/.codex/skills/` | Codex side: risk-routed Claude gate with conditionally mandatory Kimi specialist review |
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

shared_runtime_dir="${XDG_DATA_HOME:-$HOME/.local/share}/gated-development-skills"
mkdir -p "$shared_runtime_dir"
install -m 0755 shared/scripts/kimi-review.sh "$shared_runtime_dir/kimi-review.sh"

for runtime in .claude .codex .kimi-code; do
  mkdir -p "$HOME/$runtime/skills"
  cp -R shared/skills/bootstrap-project shared/skills/finish-pr "$HOME/$runtime/skills/"
done
```

Selected Kimi reviews use the native sandbox: `sandbox-exec` on macOS or
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
independently. Selected Kimi review needs an installed and authenticated
`kimi` CLI plus the shared runner installed above. The runner uses Kimi's
explicit session ID, native prompt-mode progress, built-in subagents, and an
empty skills directory; it never silently degrades a selected Kimi review.
With a task/session key, its small continuity records live under
`${XDG_CACHE_HOME:-~/.cache}/gated-development-skills/kimi-review-state/`.
Without a key, the review has no reusable session or checkpoint. Kimi's own
review-only config, credentials, sessions, and logs are isolated under the
adjacent `kimi-review-runtime/` directory, partitioned by source
`KIMI_CODE_HOME` profile.

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

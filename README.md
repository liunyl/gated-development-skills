# gated-development-skills

Gate skills for Claude Code, Codex CLI, and Kimi Code. The Codex-side
`claude-gated-development` skill is complexity-routed: local, reversible,
single-path work with a direct check skips external review, while concrete
complex or high-risk work uses Claude as the sole mandatory external gate for
planning and final reviews. Optional Kimi review is limited to named
concurrency, idempotency, transaction, tenant-isolation, and distributed-state
risks; Kimi quota or transport failure does not block Claude. Its real quant
backtests remain gated before their first run. Each Claude review mode starts
with the full task; after fixes are committed, later rounds in the same
persistent Claude session can use `--since <previous-reviewed-head>` to send
only the new commit range plus a full-task summary. Optional Kimi reviews use a
fresh full snapshot, may use built-in subagents, and may not chain to another
external reviewer or review gate.

| Skill | Lives in | Purpose |
|-------|----------|---------|
| `codex-gated-development` | Claude Code — `~/.claude/skills/` | Claude side: gate before Claude starts real work |
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

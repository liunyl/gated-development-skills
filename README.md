# gated-development-skills

Gate skills for Claude Code, Codex CLI, and Kimi Code. The Codex-side
`claude-gated-development` skill is complexity-routed: local, reversible,
single-path work with a direct check skips external review, while concrete
complex or high-risk work uses concurrent independent Claude + Kimi planning
and final reviews. Its real quant backtests remain gated before their first
run.

| Skill | Lives in | Purpose |
|-------|----------|---------|
| `codex-gated-development` | Claude Code — `~/.claude/skills/` | Claude side: gate before Claude starts real work |
| `claude-gated-development` | Codex CLI — `~/.codex/skills/` | Codex side: route complex/high-risk work through Claude + Kimi review |
| `kimi-gated-development` | Kimi Code — `~/.kimi-code/skills/` | Kimi side: judgment-triggered dual gate — Claude and Codex review in parallel, each reusing one persistent session per task across all review rounds |

## Install on a new machine

```bash
git clone git@github.com:liunyl/gated-development-skills.git
cd gated-development-skills

mkdir -p ~/.claude/skills ~/.codex/skills ~/.kimi-code/skills
cp -R claude/skills/codex-gated-development ~/.claude/skills/
cp -R codex/skills/claude-gated-development ~/.codex/skills/
cp -R kimi/skills/kimi-gated-development ~/.kimi-code/skills/
```

That's it — each tool auto-discovers skills under its `skills/` dir.

`kimi-gated-development` needs both the `claude` and `codex` CLIs installed
and authenticated; its reviewers are review-only (read-only tool surface /
sandbox) and keep one session per task per reviewer, so later rounds resume
instead of reloading context. It installs to Kimi's private skill dir
(`~/.kimi-code/skills/`), NOT the shared `~/.agents/skills/`: Codex and other
agents scan the shared dir, and they must not adopt a skill whose two
reviewers are themselves.

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

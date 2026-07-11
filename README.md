# gated-development-skills

Two mirror-named gate skills that force a planning/verification workflow before
any non-trivial implementation or backtest work.

| Skill | Lives in | Purpose |
|-------|----------|---------|
| `codex-gated-development` | Claude Code — `~/.claude/skills/` | Claude side: gate before Claude starts real work |
| `claude-gated-development` | Codex CLI — `~/.codex/skills/` | Codex side: gate before Codex starts real work |

## Install on a new machine

```bash
git clone git@github.com:liunyl/gated-development-skills.git
cd gated-development-skills

mkdir -p ~/.claude/skills ~/.codex/skills
cp -R claude/skills/codex-gated-development ~/.claude/skills/
cp -R codex/skills/claude-gated-development ~/.codex/skills/
```

That's it — each tool auto-discovers skills under its `skills/` dir.

## Install Codex plugin adapters

From the repository root:

```bash
codex plugin marketplace add ./codex
codex plugin add pr-review-toolkit@gated-development-skills
codex plugin add code-simplifier@gated-development-skills
codex plugin add frontend-design@claude-plugins-official
```

The first two plugins adapt upstream Claude-only `agents/` and `commands/`
layouts into Codex skills. Frontend Design already contains a Codex-compatible
skill, so install it directly from the official marketplace.

# Repository guidance

Keep changes to the shared and runtime-specific skills tool-neutral unless the
target directory is explicitly runtime-specific.

<!-- BEGIN bootstrap-project: engineering-standards -->
## Engineering standards

- Explain non-obvious intent, invariants, ownership, failure behavior, compatibility constraints, and performance or safety tradeoffs near the affected code. Do not restate syntax or names.
- Add or update documentation comments for public APIs when the language supports them.
- Correct stale nearby comments while changing behavior.
- Treat architecture updates as claim-driven. For implementation work, update current architecture only when a changed module boundary, core flow, ownership or lifecycle, durable or wire format, external integration, or system-level invariant makes an existing claim or core model false or materially incomplete. Leave it unchanged when no such claim exists. Dedicated documentation work may correct inaccuracies, fill core-design gaps, or consolidate sediment.
- When a change introduces, removes, splits, or merges a durable module, update the architecture taxonomy, the relevant focused documents, and the architecture index (`docs/architecture/README.md` by default, or its existing equivalent) in the same change.
- Keep the overview focused on system context, high-level flows, cross-cutting invariants, and navigation. A repository with at most one durable module may keep readable architecture detail in its overview. When multiple durable modules emerge or detail needs independent navigation, use focused documents and update the architecture index (`docs/architecture/README.md` by default, or its existing equivalent).
- Keep architecture as a compact, present-tense model of current core design and stable rationale. Put change-specific motivation and before/after explanation in the pull request or commit, and keep local algorithms, representation details, and performance mechanics near the affected code; omit those narrower details from architecture rather than cataloging them as non-architectural.
- Revise and consolidate existing architecture prose so it stands on its own without the change that produced it. Follow the authoring standard linked from `docs/README.md`.
- Treat `docs/plans/` and `docs/superpowers/` as historical change context, not authoritative descriptions of the current code.
- Before unfamiliar work, read `docs/README.md` and the relevant architecture documents.
- When code and documentation disagree, treat code as authoritative and repair the documentation in the same change.
<!-- END bootstrap-project: engineering-standards -->

## Verification

```bash
sh tests/test-engineering-infrastructure.sh
```

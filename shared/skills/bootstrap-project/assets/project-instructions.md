<!-- BEGIN bootstrap-project: engineering-standards -->
## Engineering standards

- Explain non-obvious intent, invariants, ownership, failure behavior, compatibility constraints, and performance or safety tradeoffs near the affected code. Do not restate syntax or names.
- Add or update documentation comments for public APIs when the language supports them.
- Correct stale nearby comments while changing behavior.
- When a change introduces, removes, splits, or merges a durable module, update the architecture taxonomy, the relevant focused documents, and `docs/architecture/README.md` in the same change.
- Keep the overview focused on system context, high-level flows, cross-cutting invariants, and navigation; put independently explainable subsystem detail in focused documents rather than continually growing one overview.
- Treat `docs/plans/` and `docs/superpowers/` as historical change context, not authoritative descriptions of the current code.
- Before unfamiliar work, read `docs/README.md` and the relevant architecture documents.
- When code and documentation disagree, treat code as authoritative and repair the documentation in the same change.
<!-- END bootstrap-project: engineering-standards -->

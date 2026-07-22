# Documentation

Start with the [architecture index](architecture/README.md) and relevant
current-architecture documents. Use plans only when reconstructing the
reasoning behind a particular commit or PR.

`docs/architecture/` tracks the current code. `docs/plans/` and
`docs/superpowers/` preserve historical design and implementation plans; they
are not authoritative for the current code and are not maintained as the
architecture evolves.

Architecture documentation must stay evidence-grounded. When a change alters a
module boundary, core flow, durable format, lifecycle, or external integration,
update the corresponding architecture document in the same change. Code is
authoritative when documentation is stale.

## Architecture

- [System overview](architecture/01-overview.md)

# Documentation

This directory records the repository's durable design and implementation
plans. Read [the architecture index](architecture/README.md) and its linked
overview before changing an unfamiliar subsystem; use `plans/` and
`superpowers/` for historical planning context.

Architecture documentation must stay evidence-grounded. When a change alters a
module boundary, core flow, durable format, lifecycle, or external integration,
update the corresponding architecture document in the same change. Code is
authoritative when documentation is stale.

## Architecture

- [System overview](architecture/01-overview.md)

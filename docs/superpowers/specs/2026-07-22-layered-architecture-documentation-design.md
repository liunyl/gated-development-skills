# Layered Architecture Documentation Design

## Goal

Keep project documentation useful as a repository grows: discover the real
module structure before bootstrap writes prose, document durable modules in a
navigable hierarchy, and keep current architecture separate from historical
design and implementation plans.

## Documentation roles

`docs/README.md` is the documentation entry point. It explains the reading
order and separates two kinds of evidence:

- `docs/architecture/` describes the current code. Its index and documents must
  be updated in the same change as affected module boundaries, flows, formats,
  lifecycles, or integrations.
- `docs/plans/` and `docs/superpowers/` preserve design and implementation
  decisions made for particular changes. They are historical context tied to
  those changes and are not authoritative for the current code.

Code remains authoritative when current architecture documentation is stale.

## Bootstrap workflow

Before drafting documentation, bootstrap reads repository instructions, the
root README, existing documentation, manifests, entry points, and the source
tree. It then samples implementation and tests around apparent boundaries so
directory names alone do not become architecture claims.

The parent agent records an evidence-backed module map before writing prose.
For each durable module, the map identifies its responsibility, concrete source
paths, and intended architecture-document destination. A durable module has an
independent responsibility and a meaningful interface, data flow, or lifecycle;
a directory or file alone is not enough.

The module map determines the documentation taxonomy:

- The overview contains system context, high-level components and flows,
  cross-cutting invariants, and navigation.
- Each evidenced durable module that needs independent explanation gets one
  focused, numbered subsystem document linked from the architecture index.
- Small repositories may keep one overview when they have at most one durable
  module and the focused detail remains readable.
- Empty repositories get a minimal documentation entry point, architecture
  index, and overview that state what is currently known. Bootstrap does not
  invent speculative module documents.

When two or more independent durable modules need documentation and subagents
are available, the parent delegates bounded module research and drafting. The
parent retains ownership of taxonomy, cross-cutting behavior, integration,
source-map validation, and resolving overlaps or contradictions. Tiny projects
and runtimes without subagents complete the same workflow locally.

## Ongoing maintenance

Engineering instructions require each code change to consider whether it
introduces, removes, splits, or merges a durable module. Such a change updates
the architecture taxonomy, the relevant focused documents, and the indexes in
the same change. Internal changes to an existing module update that module's
document; they do not create a document for every directory or file.

The overview stays a system-level map instead of accumulating all subsystem
detail. As an initially empty repository gains durable modules, maintainers add
focused documents and navigation rather than continually extending a single
overview.

## Implementation

The existing `bootstrap-project` skill will gain the module-map-first workflow,
conditional delegation, empty-project behavior, and documentation-role rules.
Its managed `AGENTS.md`/`CLAUDE.md` block will gain the ongoing taxonomy and
index-maintenance rules. The repository's own managed blocks and documentation
entry point will be synchronized with the asset.

The existing dependency-free engineering-infrastructure test will assert these
contracts. No new generator, validator, dependency, or document type is needed.

## Alternatives considered

One document per top-level source directory is deterministic but confuses file
layout with architecture and creates noise. A line-count threshold for splitting
the overview is easy to automate but reacts only after the document becomes
unwieldy. Evidence-backed durable boundaries require judgment, but they match
the information future agents need and avoid both speculation and monoliths.

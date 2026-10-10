# Deprecated

Retired workspace files go here instead of being deleted. See the
[cleanup review](../docs/cleanup-review.md) for the current refactor.

## 2026-10-09: shared Linux Compose definitions

Eight originals are at `2026-10-09/stacks/<node>/<app>/docker-compose.yml`:

- Nodes: grinder, mochaPot, percolator, sieve.
- Apps: komodo-periphery, scrutiny-collector.
- Original paths: `stacks/<node>/<app>/docker-compose.yml`.
- Replacement: thin files at the original paths extend
  [`stacks/_shared/`](../stacks/_shared/README.md), retaining node-local mounts and devices.
- Evidence: four identical Periphery definitions; four collectors share the same
  service settings, with mochaPot's config mount and percolator's second disk retained.
  Active callers still use the original paths; no caller reads this archive.

To undo, first move each replacement to a new dated archive, then move these
originals back to their recorded paths. Do not overwrite a file. Once no active
file references `_shared/`, that directory can also be moved here. No deployed
services were changed by this refactor.

For a future retirement, use `Deprecated/YYYY-MM-DD/<original-relative-path>`.
Record the original path, replacement, evidence that it is unused and how to
restore it in this index. Review active references and file-discovery rules
before moving it; an archived copy must not become another deployment input.

Restoration means moving the archived file back to its recorded original path,
after checking that an active replacement would not be overwritten.

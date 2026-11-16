# deprecated/

The fleet as it was before the rebuild of November 2026, kept at its old paths
and not edited. It is here so the new build can be checked against, and built
from, what worked before. The same state is at tag `freeze-2026-10`.

**Nothing in this folder is used.** No script, test or node reads it, CI does
not run it, and Dependabot does not watch it. Do not fix things here. To reuse
a file, move it out to where it belongs and record that in
[`docs/carry-over-map.md`](../docs/carry-over-map.md), which lists what each
part was replaced by and which parts are still waiting to be rebuilt ("Source").

| Here | What it was |
|---|---|
| [`runbook.md`](runbook.md) | Every decision from 2026-09-15 to 2026-10-28, with its reasons. Comments in the live code that cite "runbook" with a date before 2026-11-16 mean this file |
| [`README.md`](README.md), [`PROJECT.md`](PROJECT.md), [`docs/MAP.md`](docs/MAP.md) | The old front page, project card and map |
| [`docs/`](docs) | The September 2026 network audit, the recovery kit (flask), and the guide to the local LLMs on roastery |
| [`bootstrap/`](bootstrap) | The container that served node setup from roastery. Replaced by the purrbrews-bootstrap repository |
| [`init/`](init) | Fresh Debian to ready node, in one script, plus roastery's PowerShell equivalent. Partly replaced by purrbrews-bootstrap; the rest is the source for its payload |
| [`stacks/roastery/`](stacks/roastery) | The Windows workstation: local LLMs and game mode, the backup target, the recovery kit's builder, its agents |
| `stacks/<node>/` | Per-node copies that were merged into one folder each (Traefik, Periphery, the Scrutiny collector, restic settings), and cellar's wake-roastery timer |
| [`stacks/_lib/purrbrews.ps1`](stacks/_lib/purrbrews.ps1), [`tests/`](tests) | The PowerShell twin of the shared scripts and the tests for things archived here |

Paths inside these files are as they were written: they point at a layout that
no longer exists.

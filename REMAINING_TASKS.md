# DFTEngine Remaining Tasks

Updated: 2026-07-26

DFTEngine has complete contracts and a substantial native subset, but M2-M6
remain partial. These are package/platform completion tasks, not release
authorization tasks.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| DFT-1 | P1 | DFTEngine | Implement scan compression with decompressor/compactor insertion and coverage validation. | Canonical IR transformations preserve functional/test connectivity, compressed pattern replay proves declared coverage, ambiguous mappings block, and design diffs plus success/failure fixtures are retained. |
| DFT-3 | P1 | DFTEngine and memory backend provider | Implement the memory-BIST execution path and macro legality validation. | The typed macro binding produces a concrete canonical transformation or external result, verifies process/macro/helper-cell identity and bytes, validates controller/pattern/compactor behavior, and never treats protocol presence as completion. |
| DFT-4 | P1 | DFTEngine and external format backend | Implement qualified cycle-accurate STIL and WGL import/export. | Standard semantics round-trip against independent fixtures, bind timing/waveform/procedure data, reject lossy constructs, retain exact artifacts, and pass ToolQualification-ready correlation. |
| DFT-5 | P1 | DFT evidence workflow | Retain an independent process corpus and oracle evidence for scan, ATPG, BIST, and pattern paths. | Corpus cases bind PDK, cell/macro library, implementation, oracle, request digest, raw outputs, coverage universe, and downstream evidence without DFTEngine issuing trust or release eligibility. |

## Completed P1 tasks

| ID | Completed | Evidence |
|---|---|---|
| DFT-2 | 2026-07-26 | Process-specific ATPG separates model generation from independent pattern verification, requires distinct model/verifier identities, validates capture timing against declared DFT clocks, retains timing and verifier identity per fault, applies the same contract to external completed results, and covers success, missing verifier, invalid timing, and verifier rejection. Independent process qualification remains DFT-5. |

## External prerequisites

Tool trust, downstream equivalence/DRC/LVS/PEX gates, human approval, resume,
and release authorization remain external. Those conditions must not be
collapsed into a DFTEngine success flag.

## Evidence reviewed

- `README.md`
- `DESIGN.md`
- `INTERFACES.md`
- `IMPLEMENTATION_PLAN.md`
- `MILESTONES.md`
- `GOAL_STATUS.md`
- Scan, ATPG, BIST, format, and evidence implementation paths
- `Sources` incomplete-implementation marker scan

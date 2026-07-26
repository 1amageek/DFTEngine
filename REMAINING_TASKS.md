# DFTEngine Remaining Tasks

Updated: 2026-07-26

DFTEngine has complete native structural P1 paths for scan compression and
memory BIST. The remaining P1 gates require standard-format or independent
process evidence that must be supplied by the owning provider and qualification
workflow; they are not hidden native fallbacks.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
No package-owned P1 implementation remains.

## Completed P1 tasks

| ID | Completed | Evidence |
|---|---|---|
| DFT-1 | 2026-07-26 | Canonical scan compression inserts process-mapped decompressor/compactor cells, binds every external channel and internal chain, rejects ambiguous mapping manifests, retains design diffs, and completes a 2,048-chain debug transformation in 0.58 seconds against a five-second budget. Compressed ATPG coverage still requires a qualified semantic replay provider. |
| DFT-2 | 2026-07-26 | Process-specific ATPG separates model generation from independent pattern verification, requires distinct model/verifier identities, validates capture timing against declared DFT clocks, retains timing and verifier identity per fault, applies the same contract to external completed results, and covers success, missing verifier, invalid timing, and verifier rejection. Independent process qualification remains DFT-5. |
| DFT-3 | 2026-07-26 | Native memory BIST verifies process/PDK-bound mapping bytes, exact targets, macro types, algorithms, clock domain and pin connectivity, inserts canonical mux/controller/compactor/signature connectivity, and retains the transformed design, diff, and structure. External completed results without transformed evidence are rejected. |

## External prerequisites

| Former ID | Owner | Required evidence |
|---|---|---|
| DFT-4 | Standard-pattern format provider | Complete the accepted `docs/adr/0001-production-dft-provider.md` boundary. The separate rich STIL model, validator, fail-closed codec, and checked-in retained-byte round-trip fixture are implemented. Remaining work is the explicit ATPG/scan/response conversion contract, real OpenROAD scan insertion, Yosys functional-mode equivalence, Icarus retained-artifact replay, exact invocation artifacts, and ToolQualification-ready correlation. The compact native pattern IR remains unchanged. |
| DFT-5 | DFT evidence workflow | Independent process corpus and oracle observations binding the PDK, cell/macro library, implementation, request digest, raw output, coverage universe, and downstream evidence. |

Tool trust, compressed-pattern semantic replay, downstream
equivalence/DRC/LVS/PEX gates, human approval, resume, and release authorization
remain external. Those conditions must not be collapsed into a DFTEngine
success flag.

## Evidence reviewed

- `README.md`
- `DESIGN.md`
- `INTERFACES.md`
- `IMPLEMENTATION_PLAN.md`
- `MILESTONES.md`
- `GOAL_STATUS.md`
- Scan, ATPG, BIST, format, and evidence implementation paths
- `Sources` incomplete-implementation marker scan

# DFTEngine Remaining Tasks

Updated: 2026-07-26

DFTEngine has complete native structural P1 paths for scan compression, memory
BIST, exact uncompressed realized-scan ATPG execution plans, and conversion to
the accepted STIL subset. The remaining profile gates require real-tool replay,
equivalence, or independent process evidence supplied by the owning provider
and qualification workflow; they are not hidden native fallbacks.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
No package-owned P1 implementation remains.

## Completed P1 tasks

| ID | Completed | Evidence |
|---|---|---|
| DFT-1 | 2026-07-26 | Canonical scan compression inserts process-mapped decompressor/compactor cells, binds every external channel and internal chain, rejects ambiguous mapping manifests, retains design diffs, and completes the 2,048-chain debug regression in 1.36 seconds against a five-second budget after indexed port-binding optimization. Compressed ATPG coverage still requires a qualified semantic replay provider. |
| DFT-2 | 2026-07-26 | Process-specific ATPG separates model generation from independent pattern verification, requires distinct model/verifier identities, validates capture timing against declared DFT clocks, retains timing and verifier identity per fault, applies the same contract to external completed results, and covers success, missing verifier, invalid timing, and verifier rejection. Independent process qualification remains DFT-5. |
| DFT-3 | 2026-07-26 | Native memory BIST verifies process/PDK-bound mapping bytes, exact targets, macro types, algorithms, clock domain and pin connectivity, inserts canonical mux/controller/compactor/signature connectivity, and retains the transformed design, diff, and structure. External completed results without transformed evidence are rejected. |

## External prerequisites

| Former ID | Owner | Required evidence |
|---|---|---|
| DFT-4 | Production DFT qualification workflow | Complete the remaining external portion of `docs/adr/0001-production-dft-provider.md`. Exact realized scan chain/cell/pin/net evidence, digest-verified ATPG loading, standard-neutral shift/capture/primary-output-compare/unload plans, native semantic replay, rich STIL conversion, fail-closed codec, retained-byte round trips, a digest-bound Icarus replay provider, the typed replay CLI, and a protocol-first OpenROAD Verilog/ScanDEF canonical importer plus CLI are implemented. Remaining work is hosted real OpenROAD execution through the importer, Yosys functional-mode equivalence, hosted Icarus fault correlation including unknown-value behavior, and ToolQualification-ready corpus evidence. The compact native pattern IR remains unchanged. |
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

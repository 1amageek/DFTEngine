# DFTEngine Goal Status

## Current state

**M0 and M1 are complete. M2 has process-scoped binding plus a Liberty timing/legal-cell validator. M3 now has combinational stuck-at, bounded DFF/SDFF state-transition, explicit reset/set polarity/timing/edge contracts, qualified level-sensitive latch semantics, bounded sequential transition-fault simulation and an explicit injected model boundary for process-specific faults. M4 has canonical logic-BIST plus a typed memory adapter whose external path requires process-qualified evidence. M5-M7 have reusable artifact, oracle-correlation, request-digest-bound qualification provenance, mandatory ToolQualification process evidence, downstream evidence bundling and DFT release-review contracts. M8 production signoff and tapeout handoff is explicitly defined but not complete. The composed Xcircuite qualification/release loop is implemented and tested, but the North Star platform goal is not complete.**

| Maturity gate | Status | Evidence |
|---|---|---|
| Responsibility boundary | Complete | README.md and DESIGN.md |
| Public package products | Complete | Package.swift |
| Shared Xcircuite request/result contract | Complete | Versioned request, payload and result envelope |
| Contract build | Complete | `swift build` |
| Contract test | Complete | Swift Testing suite: 49 tests in 7 suites |
| Domain implementation | M2/M3/M4 partial | Gate-level scan transformation, process-scoped cell binding, Liberty timing/legal validation, combinational and bounded sequential ATPG including explicit reset/set and latch semantics, process-specific model injection boundary, standard pattern codecs and canonical logic-BIST transformation are validated; native memory BIST remains bounded |
| CLI implementation | Complete | `dft-engine capabilities` and `execute` with strict option validation and deterministic JSON output |
| Fixture corpus | Retained | Positive scan and negative ATPG fixtures |
| Oracle correlation | Correlation infrastructure available; process qualification not claimed | Retained expectation artifact integrity, native-result correlation and deterministic evidence digest are implemented; no independent process oracle is bundled |
| Process qualification | Not claimed | PDK/macro-specific evidence is external policy |
| Xcircuite stage adapter | M2 scan + M6 qualification + M7 release-review slices | Headless scan executor, retained-oracle qualification executor with request-digest-bound provenance persistence, mandatory ToolQualification process-evidence validator, four-domain downstream evidence bundle, DFT release executor, generic approval/resume integration, release/qualification-enabled flow spec and release artifact-integrity gate |
| End-to-end flow evidence | Composed fixture flow passed; production evidence remains open | Qualification → independent process evidence build/validation → downstream equivalence/DRC/LVS/PEX evidence bundle → approval block → generic approval record → resumed DFT release is covered by 20 focused Xcircuite DFT tests and 55 combined DFT/runtime validation tests; the release packet re-verifies every retained reference |
| Release readiness | Blocked by production evidence | Requires independently generated process-scoped oracle/evidence record, production-qualified cell/macro evidence, real equivalence/DRC/LVS/PEX artifacts, review approval and external result correlation |

## Function status

| Function | Contract | Implementation | Validation corpus | Qualification |
|---|---|---|---|---|
| Fault model | Implemented | Deterministic family and universe validation | Fixture coverage | Smoke checked |
| Scan architecture | Implemented | Deterministic chain planner | Positive fixture | Smoke checked |
| Scan insertion | Implemented | Digest-verified canonical snapshot transformation, explicit clock/reset binding, validator pass and design diff | DFTEngine tests + CLI fixture | Unqualified helper/library mapping |
| ATPG | Partial implementation | Declared-fault backend plus extracted combinational stuck-at, bounded DFF/SDFF scan-shift/capture, explicit reset/set and level-sensitive latch semantics, bounded sequential/combinational transition backends, and protocol-first process-specific model injection with result validation | Positive/negative gate-level tests, including undeclared-family, missing-model and injected-model paths | Smoke checked; retained oracle correlation is available but no process corpus is bundled |
| BIST | Partial implementation | Canonical logic gate transformation with test-mode mux/capture/compactor; memory macro path requires an external adapter and process-qualified result | Positive transformed-snapshot and adapter-gate tests | Smoke checked; helper cells and macro legality unqualified |
| Pattern formats | M5 partial | JSON, strict STIL and strict WGL codec; timed external process runner | Round-trip and malformed-input tests | Smoke checked |
| Coverage evidence | Implemented | Universe digest, outcomes and assumptions | ATPG tests and oracle correlation tests | No process qualification |

## Foundation migration boundary

`DFTFoundationEvidence` and `DFTFoundationEngine` are the explicit CircuiteFoundation boundary. The adapter preserves verified request inputs, configuration digest, design revision, producer identity, seed, output artifacts and diagnostics without replacing the DFT-specific request/result envelope. In-memory and actor-isolated file-system artifact stores are immutable and idempotent for byte-identical writes; conflicting replacements and symlink escapes are rejected.

## Goal progression

```text
contract scaffold
      ↓
deterministic contract implementation
      ↓
canonical gate-level transformation (M1)
      ↓
process-scoped scan-cell binding (M2 slice)
      ↓
combinational gate-level ATPG semantics (M3 slice)
      ↓
qualified sequential control and transition semantics (M3 slice)
      ↓
explicit process-specific fault-model boundary (M3 trust gate)
      ↓
canonical logic-BIST transformation (M4 slice)
      ↓
strict standard-pattern and timed external execution (M5 slice)
      ↓
qualification promotion gate (M6 slice)
      ↓
DFT-specific release eligibility and review/resume contract (M7 slice)
      ↓
reference-oracle correlation and process-scoped qualification
      ↓
Xcircuite downstream equivalence/DRC/LVS/PEX evidence bundle
      ↓
generic approval record and resume re-entry into DFT release gate
      ↓
```

## Completion definition

The package is not complete merely because every contract path has a deterministic implementation. The platform goal requires M0-M8. The current implementation has validated slices through the M7 release adapter, including mandatory independent process evidence validation, but production release eligibility remains blocked until retained corpus/oracle artifacts, process-qualified cell/macro evidence, downstream equivalence/DRC/LVS/PEX evidence and final approval exist.

## Current blockers

- The native gate-level ATPG covers exhaustive binary combinational simulation, bounded DFF/SDFF clock-edge/state semantics including SI/SE scan shift and functional capture, explicit reset/set polarity/timing/edge contracts, qualified level-sensitive latch semantics and bounded combinational/sequential transition semantics. Process-specific faults require an injected `DFTProcessFaultModeling` implementation and validated result; unknown primitives and process-qualified timing remain blocked.
- Native logic BIST requires explicit target pin bindings and transforms a canonical gate snapshot; controller, mux, capture and compactor helper cells still require process qualification.
- Strict STIL/WGL decoding, a timeout/tree-cleaning external runner, external stdout/stderr artifacts, retained-oracle correlation, ToolQualification process-evidence validation, an artifact-backed process-evidence builder/CLI and Xcircuite result-envelope persistence are available; actual independent process evidence and tool promotion remain integrating-flow responsibilities.
- `DFTQualificationGate` refuses promotion without complete corpus pass, oracle digest, process/PDK match, retained artifacts and approval.
- `DFTOracleCorrelationEngine` can verify normalized retained oracle expectation artifacts, compare native envelopes and emit a deterministic correlation digest; no real process corpus is bundled in this package.
- The current LogicIR does not encode process-qualified scan-capture/reset semantics; M2 timing/legal bindings and explicit architecture contracts must block ambiguous designs.
- M2 uses an explicit process-scoped manifest, exact net/pin binding and a Liberty timing/legal replacement validator; process-qualified timing evidence and legal replacement approval remain external.
- `DFT_SCAN_OUT` is an intermediate structural helper and requires a process-qualified cell mapping before physical signoff.
- Full Xcircuite release readiness remains open even though the composed qualification/independent-evidence/evidence-bundle/review-resume/release flow is implemented and tested; the immutable release packet now re-verifies all named references, while real process-qualified downstream evidence is still required.
- An external tool runner is injected through `DFTExternalToolRunning`; a concrete vendor command must be selected and qualified by the integrating project.
- Process-specific fault semantics and memory macro legality require PDK-scoped evidence outside this package.

This file must be updated by implementation agents whenever a maturity gate changes. A source file or type name alone is never evidence of implementation or qualification.

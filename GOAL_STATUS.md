# DFTEngine Goal Status

## Current state

**M0 and M1 are complete. M2 has process-scoped binding, a Liberty timing/legal-cell validator, and canonical scan-compression insertion. M3 has combinational stuck-at, bounded DFF/SDFF state-transition, explicit reset/set polarity/timing/edge contracts, level-sensitive latch semantics, bounded sequential transition-fault simulation, and independently verified process-specific outcomes with clock-bound capture timing. M4 has canonical logic- and memory-BIST transformation plus a typed external memory backend protocol. M5-M6 provide reusable artifacts, oracle correlation, and request-digest-bound evidence provenance. DFTEngine emits observations only; ToolQualification owns implementation trust and the composing flow owns downstream policy, approval, resume, and release.**

| Maturity gate | Status | Evidence |
|---|---|---|
| Responsibility boundary | Complete | README.md and DESIGN.md |
| Public package products | Complete | Package.swift |
| Canonical Foundation and domain request/result contract | Complete | Versioned request, payload and typed domain result |
| Contract build | Complete | `swift build` |
| Contract test | Complete | Timeout-bounded `DFTEngine-Package` Xcode test through the workspace verifier |
| Domain implementation | Native M2/M4 structural scope complete; M3 partial | Gate-level scan and compression transformation, process-scoped cell binding, Liberty timing/legal validation, independently replayed combinational and bounded sequential ATPG including explicit reset/set and latch semantics, process-specific model injection boundary, JSON pattern IR, and canonical logic/memory-BIST transformation are validated |
| CLI implementation | Complete | `dft-engine capabilities`, `execute`, and typed retained-artifact `replay` with strict option validation, explicit digest-bound tool descriptors, deterministic JSON output, and behavior-tested filesystem execution |
| Fixture corpus | Retained | Positive scan and negative ATPG fixtures |
| Oracle correlation | Correlation infrastructure available; process qualification not claimed | Retained expectation artifact integrity, native-result correlation and deterministic evidence digest are implemented; no independent process oracle is bundled |
| Process qualification | Not claimed | PDK/macro-specific evidence is external policy |
| Xcircuite stage composition | Direct protocol boundary | Xcircuite invokes DFT protocols and persists returned artifacts; it combines ToolQualification decisions and downstream evidence under flow-owned policy |
| End-to-end flow evidence | External composition responsibility | DFTEngine supplies typed results, request-bound provenance, and correlation observations; the composing flow owns cross-engine validation |
| Release readiness | External policy | Requires accepted process/tool evidence, real equivalence/DRC/LVS/PEX artifacts, review approval, and immutable flow records |

## Function status

| Function | Contract | Implementation | Validation corpus | Qualification |
|---|---|---|---|---|
| Fault model | Implemented | Deterministic family and universe validation | Fixture coverage | Smoke checked |
| Scan architecture | Implemented | Deterministic chain planner | Positive fixture | Smoke checked |
| Scan insertion | Implemented | Digest-verified canonical snapshot transformation, explicit clock/reset binding, process-mapped compression helpers, validator pass and design diff | DFTEngine tests + CLI fixture + 2,048-chain performance regression | Unqualified helper/library mapping |
| ATPG | Partial implementation | Declared-fault backend plus extracted combinational stuck-at, bounded DFF/SDFF scan-shift/capture, explicit reset/set and level-sensitive latch semantics, bounded sequential/combinational transition backends, and protocol-first process-specific model injection with result validation | Positive/negative gate-level tests, including undeclared-family, missing-model and injected-model paths | Smoke checked; retained oracle correlation is available but no process corpus is bundled |
| BIST | Implemented for declared structural contracts | Canonical logic and memory gate transformations with test-mode mux/controller/capture/compactor/signature networks; external backend remains injectable | Positive transformed-snapshot, macro legality, mapping identity, and external-contract tests | Smoke checked; helper cells and macro legality unqualified |
| Pattern formats and replay | M5 partial | Compact native JSON pattern IR; rich fail-closed STIL subset; digest-bound Icarus retained-artifact replay with golden and explicit stuck-at observations; headless typed CLI replay; WGL remains unsupported | STIL retained-byte round trip, malformed/unsupported input, integrity, identity, golden mismatch, result marker, timeout, cancellation, persistence, and CLI-to-provider filesystem tests | Implementation verified with fake process fixtures; real hosted Icarus correlation unqualified |
| Coverage evidence | Implemented | Universe digest, outcomes and assumptions | ATPG tests and oracle correlation tests | No process qualification |

## Foundation migration boundary

`DFTEngineExecuting`, `DefaultDFTEngine`, and `DFTResult` form the direct CircuiteFoundation boundary. The implementation preserves verified request inputs, configuration digest, design revision, producer identity, seed, output artifacts, and diagnostics. In-memory and actor-isolated file-system artifact stores are immutable and idempotent for byte-identical writes; conflicting replacements and symlink escapes are rejected.

The contract audit removed ToolQualification from DFTEngine's direct manifest and
target dependencies, removed review lifecycle state from the raw DFT diff, and
hardened external execution against non-zero exits and provenance-input
substitution. Release evidence composition is owned by the composing flow and
is not part of DFTEngine's public API.

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
declared sequential control and transition semantics (M3 slice)
      ↓
explicit process-specific fault-model boundary (M3 trust gate)
      ↓
canonical logic-BIST transformation (M4 slice)
      ↓
strict standard-pattern and timed external execution (M5 slice)
      ↓
reference-oracle correlation and evidence provenance (M6 slice)
      ↓
ToolQualification trust evaluation (external)
      ↓
DesignFlowKernel/Xcircuite review, approval, resume, and release policy
      ↓
```

## Completion definition

The package is complete only for its declared execution and evidence-emission
scope. Platform production readiness remains external and requires retained
corpus/oracle artifacts, accepted cell/macro tool evidence, downstream
equivalence/DRC/LVS/PEX evidence, and final approval.

## Current blockers

- The native gate-level ATPG covers exhaustive binary combinational simulation, bounded DFF/SDFF clock-edge/state semantics including SI/SE scan shift and functional capture, explicit reset/set polarity/timing/edge contracts, qualified level-sensitive latch semantics and bounded combinational/sequential transition semantics. Process-specific faults require an injected `DFTProcessFaultModeling` implementation, a distinct `DFTProcessFaultPatternVerifying` implementation, and capture timing validated against a declared DFT clock. Unknown primitives without an injected model and independent process qualification remain blocked.
- Native logic and memory BIST require explicit target pin bindings and
  process/PDK-bound mapping bytes. Controller, mux, capture, compactor,
  signature, and memory macro legality still require independent process
  qualification.
- Compact native JSON pattern IR, rich validated STIL exchange, a
  timeout/tree-cleaning external runner, independent retained-input Icarus
  replay, atomic raw evidence, and retained-oracle correlation are available.
  Real hosted replay correlation, independent process evidence, and tool
  promotion remain integrating-flow responsibilities.
- `DFTOracleCorrelationEngine` can verify normalized retained oracle expectation artifacts, compare native envelopes and emit a deterministic correlation digest; no real process corpus is bundled in this package.
- The current LogicIR does not encode process-qualified scan-capture/reset semantics; M2 timing/legal bindings and explicit architecture contracts must block ambiguous designs.
- M2 uses an explicit process-scoped manifest, exact net/pin binding and a Liberty timing/legal replacement validator; process-qualified timing evidence and legal replacement approval remain external.
- Scan-out is bound directly from the final scan-cell output to a canonical top-level port; no synthetic `DFT_SCAN_OUT` helper is emitted.
- Full Xcircuite release readiness remains external to this package; real accepted downstream evidence is still required.
- An external tool runner is injected through `DFTExternalToolRunning`; a concrete vendor command must be selected and qualified by the integrating project.
- Process-specific fault semantics and memory macro qualification require
  PDK-scoped evidence outside this package.

This file must be updated by implementation agents whenever a maturity gate changes. A source file or type name alone is never evidence of implementation or qualification.

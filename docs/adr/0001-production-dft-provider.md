# ADR 0001: Production DFT Provider and Pattern Replay Boundary

- Status: Accepted
- Date: 2026-07-26
- Profile: `sky130A-open-reference-v1`

## Context

`DFTTestPatternSet` is the compact native ATPG result. It retains deterministic
binary vectors and detected fault identifiers, but it does not describe signal
groups, scan procedures, waveform tables, timing sets, shift cycles, capture
cycles, or expected responses. Extending this compact result until it resembles
STIL would mix ATPG result ownership with interchange and execution semantics.
It would also make a lossy STIL or WGL serializer appear complete.

The production flow needs all of the following:

- a real scan-inserted mapped netlist;
- deterministic ATPG over the exact fault universe;
- a standard pattern artifact with cycle and timing semantics;
- independent replay from retained bytes rather than in-memory producer state;
- functional-mode equivalence for the scan transformation;
- raw evidence that can be qualified outside DFTEngine.

## Decision

The first production profile uses the following provider composition:

| Responsibility | Selected implementation |
|---|---|
| Scan architecture and insertion | OpenROAD DFT at the profile-locked revision |
| Functional-mode equivalence | Yosys equivalence over the pre-DFT and scan-inserted mapped netlists with test mode constrained inactive |
| ATPG producer | DFTEngine process-specific native ATPG over the canonical mapped gate-level design and exact fault universe |
| Standard exchange artifact | A profile-scoped STIL 1.0 subset implemented in a separate `DFTPatternExchange` target |
| Independent pattern replay | Icarus Verilog compiling a generated replay harness against the retained scan netlist and locked cell simulation models |
| Trust decision | ToolQualification over the retained producer, exchange, replay, equivalence, and corpus evidence |

`DFTPatternExchange` owns a rich, safe value model for:

- ordered signals and signal groups;
- timing sets and waveform tables;
- named shift, load, unload, and capture procedures;
- ordered cycles with drive, compare, mask, and clock events;
- pattern bursts and procedure references;
- exact source locations and unsupported construct diagnostics during decode.

`DFTTestPatternSet` remains unchanged. Scan insertion additionally emits a
`DFTScanImplementation` artifact with the exact transformed design digest,
ordered chain cells, and cell pin/net bindings. A dedicated protocol converts a
compact ATPG result plus this realized scan implementation and explicit capture
timing into a rich exchange program. Conversion must fail with a typed error
when the source contract lacks information required by the selected STIL
profile.

The STIL codec supports only constructs declared by its capability record.
Unknown keywords, inherited timing not resolved by the supported profile,
bidirectional state, macro/procedure behavior outside the profile, and timing
expressions that cannot be represented exactly are typed failures. They are
never ignored or normalized into a successful pattern.

The replay provider consumes only retained and digest-verified inputs:

1. STIL bytes;
2. the scan-inserted mapped netlist;
3. locked cell simulation models;
4. the scan architecture and pin binding;
5. the exact fault universe.

It decodes STIL, materializes a deterministic Verilog replay harness, compiles
with the locked Icarus Verilog executable, and simulates shift/capture and fault
injection. Unknown or high-impedance values at a compare point are failures.
Every fault observation is correlated to the producer result by stable fault
identity. The replay provider does not consume the producer's in-memory
coverage result.

## Responsibility Boundary

```text
DFTEngine
  compact ATPG result + scan/timing contracts
        |
        v
DFTPatternExchange
  rich pattern program <-> retained STIL bytes
        |
        v
Icarus replay provider
  raw compile/simulation/fault observations
        |
        v
ToolQualification
  corpus, independence, integrity, and production eligibility
```

- `ScanInsertion` owns canonical scan intent and native transformations.
- `ATPGEngine` owns pattern generation and raw coverage evidence.
- `DFTPatternExchange` owns standard-format syntax and semantic round trips.
- `DFTExternalTools` owns process execution, timeout, cancellation, executable
  identity, and raw output retention.
- ToolQualification owns trust and production eligibility.
- Xcircuite owns profile composition, same-design orchestration, persistence,
  repair lineage, and release-flow evidence assembly.
- ReleaseEngine owns release authorization.

No layer in this composition adds a DFTEngine-level `productionReady` value.

## Required Qualification Corpus

The profile corpus must contain:

- a clean sequential design with at least two scan cells;
- multiple scan chains and deterministic chain ordering;
- asynchronous reset behavior;
- stuck-at-0 and stuck-at-1 observations;
- transition-delay launch and capture cycles;
- one detectable fault and one justified untestable fault;
- a malformed STIL input;
- a STIL construct outside the supported profile;
- a replay mismatch;
- an unknown-value compare point;
- a timeout and cancellation case;
- a functional-mode equivalence failure.

The buffer-only hosted acquisition probe is not sufficient for DFT
qualification.

## Exit Criteria

This decision is implemented only when:

- the rich exchange model and STIL codec have independent round-trip fixtures;
- supported STIL input is decoded and re-encoded without semantic loss;
- unsupported syntax and semantics fail with typed diagnostics;
- real OpenROAD scan insertion produces a retained mapped netlist;
- Yosys proves functional-mode equivalence and a negative case fails;
- real Icarus replay agrees with ATPG for the locked positive corpus;
- mismatch, unknown-value, malformed, timeout, and cancellation paths fail;
- producer and replay executable identities are distinct;
- exact artifacts and invocation identities are retained for
  ToolQualification;
- the package progress document no longer lists the provider as an external
  prerequisite.

## Implementation Status

Completed:

- separate `DFTPatternExchange` product and safe rich value model;
- exact structural and semantic validation;
- retained exact scan implementation identity and ordered cell/pin/net
  bindings, separate from the estimated architecture plan;
- deterministic encoding and decoding for the accepted STIL subset;
- streaming decode over retained `Data` without whole-file text or token-array
  copies, plus a 20,000-cycle five-second debug-test budget;
- checked-in retained-byte round-trip fixture;
- typed rejection of malformed input, unknown constructs, unsupported time
  units, direction violations, missing references, and incomplete cycles.

Pending:

- compact ATPG plus realized scan/timing/response conversion;
- real OpenROAD scan insertion and retained mapped netlist;
- Yosys functional-mode equivalence;
- Icarus retained-STIL replay and fault correlation;
- production-profile corpus and ToolQualification evidence.

## Consequences

The design adds a separate interchange target and an explicit conversion
boundary. This is more code than serializing compact vectors directly, but it
keeps ATPG, standard syntax, execution, qualification, and release
responsibilities independently testable. WGL remains unsupported until a
separate capability profile and correlation corpus are approved.

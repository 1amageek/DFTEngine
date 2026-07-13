# DFTEngine Requirements

## Goal

Create testable silicon structures and qualified manufacturing-test artifacts without obscuring functional intent.

## Required functions

| Function | Required behavior | Priority |
|---|---|---:|
| Fault model | Represent stuck-at, transition and declared process-specific fault families. | P0 |
| Scan architecture | Plan scan domains, chains, clocks, resets and compression constraints. | P0 |
| Scan insertion | Produce an immutable transformed design and detailed design diff. | P0 |
| ATPG | Generate deterministic patterns and compute detected, untestable and aborted faults; process-specific detection requires an injected model result and preserved model identity. | P0 |
| BIST | Represent and insert memory or logic BIST structures under explicit policies. | P1 |
| Pattern formats | Read and write standard test-pattern artifacts such as STIL and WGL. | P1 |
| Coverage evidence | Persist coverage, exclusions, assumptions and qualification provenance. | P0 |

## Required outcomes

- DFT mutations are reviewed as design changes.
- Functional equivalence or approved test-mode exceptions follow insertion.
- Coverage values cannot be reported without a declared fault universe.

## Common platform requirements

- Public execution surfaces are protocol-first, Sendable and dependency-injected.
- Requests and payloads are Codable, Hashable and schema-versioned.
- Inputs and outputs use immutable CircuiteFoundation `ArtifactReference` values.
- Diagnostics contain a stable code, severity, affected entity and suggested actions.
- Unsupported semantics and missing prerequisites produce blocked results.
- Native and external-tool backends conform to identical request and payload schemas.
- Execution capability, corpus validation, oracle correlation, process qualification and release approval remain distinct.
- Xcircuite owns flow construction, artifact persistence, qualification gates, repair loops, approval and resume.
- The package never imports Xcircuite or circuit-studio.

## Required developer surfaces

- Typed API
- Deterministic JSON CLI
- Positive and negative fixtures
- Contract and parser round-trip tests
- Reference corpus
- Capability and limitation report
- Xcircuite stage adapter tests

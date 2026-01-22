# Requirements

## Scope
- Deploy a local Ethereum network to validate an archive-node operational approach before production.
- Operate at least one archive node against the local network.
- Produce a production-grade operational plan for archive nodes.

## Functional Requirements
- Local Ethereum network deployment using any tool.
- At least one validator node.
- One archive node.
- Continuous block production.

## Archive Node Configuration Requirements
- Full historical state enabled (archive mode).
- JSON-RPC enabled.
- No pruning.
- Indexed for historical queries.

## Operational Plan Requirements
- Production-grade archive-node operational plan (primary deliverable).
- SRE perspective answers:
  - SLO for archive queries.
  - What breaks the error budget.
  - What failures are acceptable.
  - What pages an on-call engineer.

## Deliverables
- Git repository with:
  - Local network deployment.
  - Node configs.
  - Scripts or manifests.
  - Architecture and operations documentation (2-3 pages max).
- README with:
  - How to run.
  - How to inspect archive queries.
- Optional diagram.

## Constraints
- Time expectation: 5-8 hours total.
- Emphasis on architecture, operations, and SRE reasoning.
- Not focused on performance tuning or feature development.

## Assumptions
- Client and tooling choices are flexible; selection should prioritize clarity, reproducibility, and archive-mode correctness.
- Local deployment is acceptable via containers or native binaries.

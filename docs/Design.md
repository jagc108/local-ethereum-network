# Design

## Goals
- Provide a local Ethereum network that continuously produces blocks.
- Run an archive node with full historical state and JSON-RPC enabled.
- Produce a production-grade operational plan for archive nodes.

## Non-goals
- Performance tuning or benchmarking.
- Feature development beyond network and archive-node operations.

## Proposed Architecture
- Execution layer (EL) client for block execution and state storage.
- Consensus layer (CL) client for consensus and validator duties.
- One validator node (CL + EL pairing).
- One archive node (EL in archive mode paired with a non-validating CL client).

### Rationale
Post-merge Ethereum requires both EL and CL clients to fully sync and operate. The archive node is modeled as an EL in archive mode paired with a CL client that follows the chain but does not validate.

### Selected Clients
- EL: Nethermind (minority client to support client diversity).
- CL: Teku (production-grade, minority client for validator diversity).
- Validator pair: Nethermind + Teku.
- Archive pair: Nethermind (archive mode) + Teku (non-validating follower).

## Local Network Layout
- Genesis and chain configuration defined for both EL and CL.
- Validator keys and CL genesis data generated for the local network.
- EL/CL genesis artifacts generated via ethpandaops/ethereum-genesis-generator.
- Network started with a minimum of:
  - 1 validator (Teku CL) with validator keys.
  - 1 validator EL (Nethermind).
  - 1 archive EL.
  - 1 archive CL (Teku follower, non-validating).

## Deployment Approach
- Local network: Docker Compose for explicit, repo-owned configuration and reproducibility.
- Production-grade target: Kubernetes (or systemd + config management) with pinned versions, audited configs, and staged rollouts.
- Store configs, genesis files, and keys in repo-managed directories.
- Use volumes for EL and CL data directories to preserve state across restarts.
- Docker Compose layout and client config templates are documented in `DockerCompose.md`.

## Archive Node Configuration
- EL configured for archive mode with no pruning.
- JSON-RPC enabled for archive queries.
- Historical indexing enabled (transaction and log indexing as supported by the chosen client).
- CL configured as a non-validating follower to satisfy post-merge requirements.
- Client-specific flags and config values must be verified against official docs before implementation.

## Observability and Operations (Production-grade Plan)

### Monitoring
- Chain head, finalized, and safe block height for EL and CL.
- Sync status and peer count.
- JSON-RPC request rate, error rate, and latency.
- Disk usage and database growth.
- Node process health and restarts.

### Alerting
- Node not progressing (head block height stalled).
- EL and CL out of sync beyond a defined threshold.
- Archive RPC error rate above SLO.
- Disk space below a critical threshold.
- Repeated process crashes or restart loops.

### Backups and Recovery
- Preserve genesis, chain config, and validator keys (if applicable).
- Use database snapshots for archive EL data.
- Define restore procedure with integrity checks and sync verification.

### Security
- Restrict JSON-RPC exposure to local host or an internal network.
- Apply rate limits where practical for RPC.
- Store JWT secrets and validator keys outside of version control; reference via env vars or mounted files.

### Upgrades and Change Management
- Upgrade EL and CL clients in a staged manner.
- Validate compatibility between EL and CL versions.
- Maintain rollback procedure and snapshot points.

## SRE Perspective

### SLO for Archive Queries
- Availability: >= 99.9% successful RPC responses per 30-day window.
- Latency: p95 <= 1.0s for common historical queries (exact thresholds to be validated in implementation).

### Error Budget Policy
- Error budget is consumed by failed or timed-out archive queries.
- Budget is also impacted by prolonged sync stalls that make archive data unavailable.

### Acceptable Failures
- Short-lived restarts during upgrades within a planned maintenance window.
- Brief RPC degradation during controlled resync events.

### Pager Triggers
- Archive RPC unavailable or error rate exceeds SLO.
- Head block height stalls or diverges from validator node for more than a defined threshold.
- Disk usage critically low or database corruption detected.
- EL and CL connection failures (engine API or sync mismatch).

## Trade-offs
- Docker Compose is chosen for simplicity and reproducibility. Alternative tools (e.g., Kurtosis) can accelerate setup but add tool-specific dependencies and abstractions.

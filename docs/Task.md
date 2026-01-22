# Task List

## Planning and Decisions
- [x] Select EL and CL clients that support archive mode and local devnet use (Nethermind + Teku).
- [x] Confirm local deployment method: Docker Compose (explicit configs) and document the rationale.
- [x] Document production-grade target: Kubernetes (or systemd + config management) with pinned versions and staged upgrades.
- [ ] Confirm required ports, data paths, and resource needs for the selected clients.
- [x] Validate client flags and archive-mode settings against official docs before implementation.

## Network Configuration
- [x] Define chain parameters (chain ID, fork schedule, block timing).
- [x] Generate EL genesis and CL genesis data with matching parameters.
- [x] Create validator keys and deposits for at least one validator.
- [x] Prepare EL and CL config files for validator and archive nodes.
- [x] Run `scripts/generate-genesis.sh` to produce `genesis.ssz` and EL chainspec.
- [x] Run `scripts/wire-peers.sh` to configure CL static peers.

## Deployment Artifacts
- [x] Add container or service definitions for EL and CL nodes (documented in `DockerCompose.md`).
- [x] Add volumes or data directories for persistent state.
- [x] Add environment variable handling for secrets (JWT, validator keys).
- [x] Provide startup scripts or make targets for common workflows (start, stop, clean).
- [x] Run `scripts/generate-jwt.sh` and `scripts/generate-keys.sh`.

## Archive Node Enablement
- [x] Configure EL for archive mode with no pruning.
- [x] Enable JSON-RPC on the archive node.
- [x] Enable historical indexing (transactions and logs, as supported).
- [x] Configure archive CL as a non-validating follower.

## Validation
- [x] Verify block production continues over time.
- [ ] Verify archive node stays in sync with validator node.
- [x] Validate archive queries against historical blocks.

## Documentation
- [x] Document architecture and operational plan in `Design.md`.
- [x] Document requirements in `Requirements.md`.
- [x] Provide a runnable README with local setup and query examples.
- [x] Add an optional architecture diagram if it clarifies the design.

## Quality Gates
- [ ] Run formatting and validation checks (terraform or other tooling if present).
- [ ] Run security scanning if applicable (tfsec or checkov if Terraform is used).

## Future Enhancements (Optional)
- [ ] Add a second validator for redundancy testing.
- [ ] Add metrics stack (Prometheus and Grafana) for dashboards.
- [ ] Add log aggregation and alerting rules.

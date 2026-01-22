# Operational Plan (Archive Nodes)

This document covers Part 3 (Operational Plan) and Part 4 (SRE Perspective) of the challenge. It describes how to operate Ethereum archive nodes in a production setting.

---

## 1) Goals and Scope

Primary objectives:
- Provide reliable historical query access for compliance, analytics, and forensics.
- Maintain full historical state (no pruning) with predictable performance.
- Enable safe upgrades, rollbacks, and disaster recovery.

Out of scope:
- Performance micro-optimizations at the client level.
- Application-specific analytics pipelines.

---

## 2) Architecture Overview (Production)

Components:
- Archive Execution Layer (EL) nodes in archive mode (no pruning).
- Consensus Layer (CL) nodes as followers (non-validating) to support post-merge sync.
- RPC access tier for read-only traffic (auth, rate limits, caching).
- Observability stack (metrics, logs, traces, alerts).
- Backups and snapshot storage for EL data.

Topology:
- Minimum 2 archive EL nodes per environment for redundancy.
- At least 1 CL follower per archive EL (paired).
- RPC traffic routed via internal load balancer to archive EL nodes.
- Separate validator infrastructure (if needed) is isolated from archive tier.

### Deployment platform (Kubernetes vs standalone)
Guidance:
- **Standalone servers (bare metal or VMs)** are commonly preferred for archive nodes due to heavy disk IO and predictable performance. They reduce orchestration overhead and simplify low-level storage tuning.
- **Kubernetes** can work if you use StatefulSets with pinned nodes, local NVMe, and careful IO isolation. It is better for operational consistency (deployments, rollbacks, scaling) but can add complexity around storage and networking.

Recommendation:
- For production archive nodes, prefer **standalone servers** when IO and latency are critical and workloads are steady.
- Use **Kubernetes** when you already have strong platform maturity and can guarantee storage performance (local NVMe + dedicated nodes).

---

## 3) Data and Storage Strategy

Archive storage characteristics:
- Full historical state requires large storage and continuous growth.
- IO performance (disk throughput and IOPS) strongly impacts query latency.

Recommendations:
- Use high-performance SSD (NVMe) with provisioned IOPS.
- Plan capacity with at least 30–50% headroom.
- Separate data volume from OS volume.
- Enable filesystem-level monitoring (disk latency, queue depth).

Backups:
- Periodic snapshots of EL data volume (weekly + daily incremental).
- Store snapshots in object storage with lifecycle policies.
- Validate snapshots with periodic restore tests.

---

## 4) Networking and Access

Inbound:
- JSON-RPC exposed only through an authenticated gateway.
- Rate limits per client and per method.
- WAF or internal firewall rules (no public raw RPC).

Outbound:
- CL and EL must reach each other locally (Engine API).
- EL nodes need P2P connectivity to sync (outbound).

Security:
- JWT secrets stored in secrets manager and mounted at runtime.
- No plaintext private keys in repo or images.
- Principle of least privilege for service accounts.

### Gateway / LB recommendations
Archive nodes should not be exposed directly. Use a gateway in front:
- **L7 Gateway (RPC)**: Kong Gateway, NGINX Ingress, or Envoy for auth, rate limits, and request logging.
- **Cloud LB**: AWS ALB in front of the gateway for HTTP/HTTPS termination.
- **P2P traffic** should bypass L7 gateways; use direct inbound rules or an L4 load balancer if required.

Recommendation:
- RPC: Gateway + ALB (or equivalent) for auth + rate limits + observability.
- P2P: Direct node exposure with strict firewall rules.

---

## 5) Observability

Metrics (minimum):
- EL: head block, sync status, peer count, DB size, RPC latency and error rate.
- CL: head slot, finalized slot, sync status, peer count.
- System: CPU, memory, disk IOPS, disk usage, network.

Logs:
- Centralized log collection (structured if possible).
- Retention aligned to compliance needs.
- Error patterns and restart loops highlighted.

Tracing:
- Optional distributed tracing at the RPC gateway.

Dashboards:
- Archive query success rate and latency.
- Chain head progression and finality status.
- Disk growth and storage saturation.

### Prometheus + Grafana + Loki stack
Recommended stack:
- **Prometheus** scrapes metrics endpoints from EL/CL and node exporters.
- **Grafana** visualizes metrics dashboards and RPC SLOs.
- **Loki** stores logs; Grafana provides log search and correlation.

Implementation notes:
- Enable metrics on EL/CL clients and expose a scrape endpoint.
- Add node exporter for host-level CPU, memory, disk, and network.
- Use Promtail (or Fluent Bit) to ship logs into Loki.

Dashboards:
- Use official Grafana dashboards if provided by client vendors.
- Otherwise use community dashboards for Nethermind and Teku as a baseline.

### Nethermind (metrics + health)
From official docs:
- Enable metrics (examples):
  - `--Metrics.Enabled true` (CLI option)
  - `--metrics-enabled true` (CLI option in Docker examples)
- Metrics options (examples): `--Metrics.ExposeHost`, `--Metrics.ExposePort`, `--Metrics.IntervalSeconds`.
- Health checks:
  - Enable: `--healthchecks-enabled true`
  - Query: `curl http://<host>:<rpc-port>/health`

Grafana:
- Official guidance exists for Prometheus + Grafana integration.
- Reference repo: `github.com/NethermindEth/metrics-infrastructure` (dashboards + config).

### Teku (metrics)
From Teku docs (use metrics):
- Enable metrics: `--metrics-enabled`
- Metrics endpoint: `http://<host>:8008/metrics` (Prometheus scrape target uses port 8008 in the Teku example).
- Metrics categories are prefixed by the category specified in `--metrics-categories`
  - Example categories shown: `BEACON,PROCESS,LIBP2P,JVM,NETWORK,PROCESS`
- If Prometheus is on a different host, add it to `--metrics-host-allowlist` to avoid DNS rebinding attacks.

Prometheus scrape example (from Teku docs):
```yaml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: "teku-dev"
    scrape_timeout: 10s
    metrics_path: /metrics
    scheme: http
    static_configs:
      - targets: ["localhost:8008"]
```

Prometheus UI: `http://localhost:9090`

Grafana:
- Teku dashboard example: Grafana dashboard ID **13457**.

### Teku (logging)
From Teku docs (configure logging):
- Log level: `--logging` with levels `OFF`, `FATAL`, `ERROR`, `WARN`, `INFO`, `DEBUG`, `TRACE`, `ALL` (default `INFO`).
- Destination: `--log-destination` with `BOTH`, `CONSOLE`, `DEFAULT_BOTH`, `FILE` (default `DEFAULT_BOTH`).
- Log file: `--log-file` to specify the log file path.
- Default log directory:
  - macOS: `~/Library/teku/logs`
  - Linux/Unix: `$XDG_DATA_HOME/teku/logs` or `~/.local/share/teku/logs`
  - Windows: `%localappdata%\\teku\\logs`
  - Docker image default: `/root/.local/share/teku/logs`
- For production, Teku recommends `CONSOLE` or `FILE` so all logs are in one place.

Additional logging options:
- `--log-color-enabled` (colorized console logs)
- `--log-include-events-enabled` (frequent update events, slot/attestation)
- `--log-include-validator-duties-enabled` (validator duty details)

Operational note:
- Use a log ingestion tool (e.g., Logstash) to parse logs and alert on anomalies.
- The `log_level` API method can change log level while Teku is running.

---

## 6) Sizing and Capacity Planning

Inputs:
- Expected QPS and query mix (historical reads, traces, logs).
- Retention targets (how far back queries go).
- Forecasted chain growth.

Sizing approach:
- Start with a baseline node profile (CPU, memory, NVMe).
- Load-test with representative query mix.
- Scale horizontally by adding archive nodes behind the RPC tier.

---

## 7) Deployment and Change Management

Deployment approach:
- Staged rollouts: dev -> staging -> production.
- Canary upgrades for one archive node at a time.

Version control:
- Pin EL and CL versions per environment.
- Track configuration changes in code review.

Rollback:
- Keep the previous container image and config bundle.
- Restore from snapshots if database incompatibility is detected.

---

## 8) Reliability and Incident Response

Runbooks should cover:
- Archive node stalls (no head progression).
- EL/CL connection failures (Engine API).
- RPC outage or latency spikes.
- Disk full or IO saturation.
- Data corruption / failed restore.

Escalation:
- On-call primary for RPC availability.
- Storage/infra escalation for persistent IO or disk issues.

---

## 9) SRE Perspective (Part 4)

SLO for archive queries:
- Availability: >= 99.9% successful RPC responses per 30-day window.
- Latency: p95 <= 1.0s for common historical queries (exact thresholds validated by load tests).

What breaks the error budget:
- RPC errors or timeouts above SLO thresholds.
- Extended EL/CL desync preventing historical queries.
- Storage saturation causing high latency or failures.

Acceptable failures:
- Short, planned maintenance windows with reduced capacity.
- Single-node failure when redundant nodes are healthy.
- Brief resync after safe upgrades within the window.

What pages on-call:
- Archive RPC is down or error rate spikes.
- Head block stalls or diverges from validator chain.
- Disk usage critical (risk of full disk).
- EL/CL Engine API disconnects or repeated restarts.

---

## 10) Validation Checklist (Production Readiness)

- [ ] Archive EL configured with no pruning.
- [ ] CL follower connected and stable.
- [ ] RPC access gated (auth + rate limits).
- [ ] Monitoring dashboards and alerts in place.
- [ ] Backups and restore tested.
- [ ] Runbooks documented and exercised.
- [ ] Load testing with real query mix.

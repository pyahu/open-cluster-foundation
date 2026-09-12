# Capacity and cost planning

The `production-ha` defaults prioritize failure tolerance over minimum spend.
They are a sizing baseline for a modest platform, not an autosizing system.
Measure real ingestion and query load before changing resource requests or
retention.

## Baseline reservation

The rendered profile reserves approximately the following before application
workloads and provider system Pods:

| Resource | OCF reservation |
| --- | ---: |
| CPU requests | 8.5 vCPU |
| Memory requests | 25 GiB |
| Persistent block storage | 490 GiB |
| General worker nodes | 3 |
| Failure zones | 2 minimum, 3 preferred |
| External databases | 1 highly available PostgreSQL service for Grafana |
| Object-store buckets | 5: Loki chunks/ruler/admin, Tempo and Thanos |

The CPU and memory figures include three general nodes' Alloy, node-exporter
and Loki-canary DaemonSets, two Prometheus replicas and three Alertmanager
replicas. They exclude cloud CNI/CSI Pods, DNS, the managed control plane,
application workloads, Kafka, Valkey, PostgreSQL clusters, ZITADEL and
Infisical.

Start with three general workers of 8 vCPU and 24 GiB each. After reserving 20%
for the operating system, Kubernetes and rollout surge, that shape leaves about
10.7 vCPU and 32.6 GiB for applications beyond the OCF base. Add dedicated,
tainted node pools for databases or high-throughput messaging instead of
consuming that margin.

Use these admission equations for a proposed node pool:

```text
usable CPU = node count × allocatable vCPU × 0.80
usable memory = node count × allocatable GiB × 0.80
application CPU budget = usable CPU - 8.5
application memory budget = usable memory - 25
```

Both application budgets must remain positive after simulating one unavailable
node and the largest rolling-update surge. CPU limits are intentionally not the
capacity input; scheduling is driven by requests.

## Object-storage estimate

Estimate each signal independently and add 30% for indexes, compaction overlap,
multipart uploads and forecast error:

```text
Loki GiB = uncompressed logs GiB/day × measured compression ratio × 30 × 1.30
Tempo GiB = spans/second × average encoded bytes/span × 86400 × 30 × 1.30 / 2^30
Thanos raw GiB = active series × 2880 samples/day × measured bytes/sample × 30 × 1.30 / 2^30
```

The Thanos estimate needs additional space for the 5-minute and 1-hour
downsampled blocks retained for 180 and 365 days. Use actual bucket growth from
a representative week to price those tiers; do not infer it from raw sample
count alone. Request, retrieval, replication, egress and early-deletion charges
can exceed storage cost on some providers.

## Monthly cost model

Fill in prices from the deployment region and billing account:

```text
monthly compute = sum(node hourly price × node count × 730)
monthly block storage = 490 GiB × block-storage GiB-month price
monthly object storage = estimated stored GiB × storage-tier GiB-month price
monthly database = HA PostgreSQL instance + replicas + backups + I/O
monthly network = load balancers + public IPv4 + cross-zone traffic + egress
monthly total = compute + block + object + database + network + support
```

Track forecast and actual cost per cluster. Alert at 70%, 85% and 100% of the
monthly budget, and review retention whenever object growth differs from the
forecast by more than 20% for seven days.

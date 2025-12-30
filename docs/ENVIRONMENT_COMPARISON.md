# Environment Comparison: cae-jupyterhub vs tofu_era (cae & englacial)

This document provides a thorough comparison of the three deployment approaches:
- **cae-jupyterhub**: Existing CAE deployment (eksctl + Helm)
- **cae**: New CAE deployment (tofu_era/OpenTofu)
- **englacial**: Reference tofu_era deployment

---

## Part 1: cae-jupyterhub vs cae (tofu_era)

### Major Differences

#### 1. Infrastructure Management

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **IaC Tool** | eksctl + manual Helm | OpenTofu (Terraform-compatible) |
| **State Management** | None (eksctl config files) | S3 backend with DynamoDB locking |
| **Secrets Management** | Manual (Kubernetes secrets) | SOPS encryption in Git |
| **Reproducibility** | Manual recreation needed | `tofu apply` recreates everything |

#### 2. Cluster Architecture

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **Node Groups** | 2 (main + dask-workers) | 3 (system + user + dask) |
| **Hub Isolation** | Hub competes with users on `main2` | Dedicated `system` node for Hub |
| **User Node Scaling** | min: 1 (always running) | min: 0 (scale to zero) |
| **Dask Node Scaling** | min: 1 (always running) | min: 0 (scale to zero) |

**Architecture Diagrams:**

```
cae-jupyterhub (2-node):
├── main2 (r5n.xlarge, on-demand, 1-30)
│   ├── JupyterHub Hub         ← Competes for resources
│   ├── JupyterHub Proxy       ← with user notebooks
│   ├── User Notebooks         ← on the same node
│   └── Dask Gateway
└── dask-workers (m5.*, spot, 1-30)
    └── Dask Workers

cae/tofu_era (3-node):
├── system (r5.large, on-demand, 1 fixed)
│   ├── JupyterHub Hub         ← Isolated, stable
│   ├── JupyterHub Proxy
│   └── Dask Gateway
├── user (r5.large/xlarge, on-demand, 0-30)
│   └── User Notebooks         ← Dedicated, scale-to-zero
└── dask (m5.*/m5a.*, spot, 0-30)
    └── Dask Workers
```

#### 3. Load Balancer Type

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **Type** | Classic ELB (Layer 7) | Network Load Balancer (Layer 4) |
| **WebSocket Support** | Limited (60s idle timeout) | Full support (TCP passthrough) |
| **SSL Termination** | At ELB | At NLB |
| **Annotations** | `aws-load-balancer-ssl-cert` only | Full NLB config with `nlb-target-type: ip` |

**cae-jupyterhub ELB annotations:**
```yaml
service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:..."
service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "https"
service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout: "3600"
```

**cae NLB annotations:**
```yaml
service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:..."
service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
```

#### 4. Storage Class

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **Default Storage** | gp2 | gp3 |
| **IOPS (baseline)** | 3 IOPS/GB (scales with size) | 3000 IOPS (fixed, any size) |
| **Throughput** | 128 MB/s max | 125 MB/s baseline |
| **Cost** | ~$0.10/GB/month | ~$0.08/GB/month (20% cheaper) |

#### 5. Kubernetes Version

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **Version** | 1.29 | 1.34 |
| **Notes** | eksctl cluster.yaml | terraform.tfvars |

#### 6. Instance Types

| Node Group | cae-jupyterhub | cae (tofu_era) |
|------------|----------------|----------------|
| **Main/System** | r5n.xlarge (4 vCPU, 32GB) | r5.large (2 vCPU, 16GB) |
| **User** | (shared with main) | r5.large / r5.xlarge (selectable) |
| **Dask** | m5.large → m5.4xlarge | m5.large → m5.4xlarge + m5a.* |

**Note**: cae adds AMD instances (m5a.*) for better spot availability and lower cost.

#### 7. Profile Selection

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **Available** | No | Yes |
| **Options** | Fixed: 2 CPU / 15GB | Small (2 CPU/14GB) or Medium (4 CPU/28GB) |
| **Selection Point** | N/A | At login (spawner page) |

### Minor Differences

#### 8. Helm Chart Version

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **DaskHub Chart** | Unspecified (latest) | 2024.1.1 (pinned) |
| **Dask Gateway Chart** | (included in DaskHub) | 2024.1.0 (standalone also available) |

#### 9. Namespace

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **Name** | daskhub | jupyterhub |
| **Creation** | Manual (`kubectl create ns`) | Automatic (Terraform) |

#### 10. Admin Users

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **Admins** | bgaley@berkeley.edu | mark.koenig@, neil.schroeder@ |
| **Configuration** | In daskhub.yaml | In terraform.tfvars |

#### 11. Availability Zones

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **Configured** | us-west-2a, us-west-2b | All available (auto-discovered) |
| **Node Pinning** | All nodes in us-west-2a | User nodes pinned to single AZ for PVC |

#### 12. Secrets Encryption (at rest)

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **Method** | EKS Secrets Encryption (KMS) | EKS Secrets Encryption (KMS) + SOPS |
| **KMS Key** | Manual key specified | Auto-created per environment |

#### 13. S3 Bucket

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **Bucket** | cadcat-tmp | cadcat-tmp (existing) |
| **Path** | s3://cadcat-tmp/$(JUPYTERHUB_USER) | s3://cadcat-tmp/$(JUPYTERHUB_USER) |
| **Management** | External | External (use_existing_s3_bucket=true) |

#### 14. Cost Monitoring

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **Kubecost** | Not installed | Enabled (enable_kubecost = true) |
| **CloudWatch** | Not configured | Available (enable_monitoring = false by default) |

#### 15. Backup Configuration

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **EBS Snapshots** | Manual | Automated (enable_backups = true) |
| **Retention** | N/A | 7 days |

#### 16. VPC CIDR

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **CIDR** | Default (10.0.0.0/16?) | 10.5.0.0/16 |
| **NAT Gateway** | Unknown (eksctl default) | Single NAT (cost-optimized) |
| **S3 VPC Endpoint** | Unknown | Configured (no NAT costs for S3) |

#### 17. Kernel Culling

| Setting | cae-jupyterhub | cae (tofu_era) |
|---------|----------------|----------------|
| **cull_idle_timeout** | 1200 (20 min) | 1200 (20 min) |
| **cull_interval** | 120 (2 min) | 120 (2 min) |
| **cull_connected** | true | true |
| **cull_busy** | false | false |

*Identical configuration preserved.*

#### 18. Dask Cluster Configuration

| Setting | cae-jupyterhub | cae (tofu_era) |
|---------|----------------|----------------|
| **idle_timeout** | 1800 (30 min) | 1800 (30 min) |
| **cluster_max_cores** | 20 | 20 |

*Identical configuration preserved.*

#### 19. Lifecycle Hooks

| Aspect | cae-jupyterhub | cae (tofu_era) |
|--------|----------------|----------------|
| **climakitae** | pip install at startup | pip install at startup |
| **gitpuller** | cae-notebooks repo | cae-notebooks repo |
| **Command** | Identical | Identical |

**Preserved command:**
```bash
/srv/conda/envs/notebook/bin/pip install --no-deps -e git+https://github.com/cal-adapt/climakitae.git#egg=climakitae -e git+https://github.com/cal-adapt/climakitaegui.git#egg=climakitaegui; /srv/conda/envs/notebook/bin/gitpuller https://github.com/cal-adapt/cae-notebooks main cae-notebooks || true
```

---

## Part 2: cae vs englacial (both tofu_era)

### Major Differences

#### 1. Authentication

| Aspect | cae | englacial |
|--------|-----|-----------|
| **Provider** | AWS Cognito (external) | GitHub OAuth |
| **User Pool** | cae.auth.us-west-1.amazoncognito.com | GitHub |
| **Org Restriction** | N/A (Cognito managed) | Optional (github_org_whitelist) |
| **Create New Pool** | No (use_external_cognito = true) | Yes (module creates) |

#### 2. S3 Bucket

| Aspect | cae | englacial |
|--------|-----|-----------|
| **Bucket** | cadcat-tmp (existing) | jupyterhub-englacial-* (new) |
| **Management** | External | Terraform-managed |
| **Lifecycle** | 30 days | 30 days |
| **force_destroy** | false | true |

#### 3. Dask Worker Configuration

| Setting | cae | englacial |
|---------|-----|-----------|
| **worker_cores_max** | 4 (flexible) | 1 (fixed) |
| **worker_memory_max** | 16 GB | 3 GB |
| **cluster_max_cores** | 20 | 200 |
| **Philosophy** | User flexibility | Optimized bin-packing |

**CAE philosophy**: Let users choose 1-4 cores per worker (legacy behavior).
**Englacial philosophy**: Fixed 1-core workers pack efficiently, scale to 200 total.

#### 4. Admin Users

| Aspect | cae | englacial |
|--------|-----|-----------|
| **Admins** | mark.koenig@, neil.schroeder@ | admin@example.com |
| **Config Location** | admin_users list | admin_email |

#### 5. Kubecost

| Aspect | cae | englacial |
|--------|-----|-----------|
| **Enabled** | true | true |
| **AWS CUR Integration** | Configured | Configured |

### Minor Differences

#### 6. Domain & Certificates

| Aspect | cae | englacial |
|--------|-----|-----------|
| **Domain** | hub.cal-adapt.org | hub.englacial.org |
| **Wildcard Cert** | *.cal-adapt.org | hub.englacial.org only |

#### 7. VPC CIDR

| Aspect | cae | englacial |
|--------|-----|-----------|
| **CIDR** | 10.5.0.0/16 | 10.4.0.0/16 |

#### 8. Node Group Scaling

| Node Group | cae | englacial |
|------------|-----|-----------|
| **User max** | 30 | 10 |
| **Dask max** | 30 | 100 |

#### 9. Kubernetes Version

| Aspect | cae | englacial |
|--------|-----|-----------|
| **Version** | 1.34 | 1.34 |

#### 10. User Resource Limits (fallback)

| Setting | cae | englacial |
|---------|-----|-----------|
| **cpu_guarantee** | 2 | 3 |
| **cpu_limit** | 4 | 4 |
| **memory_guarantee** | 15G | 24G |
| **memory_limit** | 30G | 30G |

*Note: These are only used when profile selection is disabled.*

#### 11. Safety Settings

| Setting | cae | englacial |
|---------|-----|-----------|
| **deletion_protection** | true | false |
| **skip_final_snapshot** | false | true |
| **enable_backups** | true | false |
| **backup_retention_days** | 7 | 1 |

*CAE has production-grade safety; englacial is for testing/iteration.*

#### 12. Container Image

| Aspect | cae | englacial |
|--------|-----|-----------|
| **Image** | pangeo/pangeo-notebook | pangeo/pangeo-notebook |
| **Tag** | 2025.01.10 | 2024.04.08 |

#### 13. Lifecycle Hooks

| Aspect | cae | englacial |
|--------|-----|-----------|
| **Enabled** | true | false (implicit) |
| **climakitae** | Installed | Not installed |
| **gitpuller** | cae-notebooks | Not configured |

---

## Part 3: cae-dev Environment

cae-dev is designed to mirror cae production as closely as possible for testing:

| Aspect | cae | cae-dev |
|--------|-----|---------|
| **Account** | 390197508439 | 992398409787 |
| **Domain** | hub.cal-adapt.org | cae-dev.example.com |
| **Authentication** | External Cognito | External Cognito (same pool) |
| **S3 Bucket** | cadcat-tmp (existing) | New (created by Terraform) |
| **Instance Types** | r5.*, m5.* | t3.*, m5.* (cheaper) |
| **Node Max Sizes** | 30/30 | 5/10 |
| **Lifecycle Hooks** | Enabled | Enabled |
| **Kubecost** | Enabled | Enabled |
| **User Node Scheduling** | Enabled (8am-5pm PT) | Enabled (8am-5pm PT) |
| **Backups** | Enabled | Disabled |
| **Auto Shutdown** | Disabled | Enabled (8 PM daily) |

---

## Summary: What Changes for CAE Users?

### Improvements
1. **Better stability**: NLB instead of Classic ELB fixes WebSocket timeouts
2. **Faster storage**: gp3 with consistent 3000 IOPS regardless of volume size
3. **Choice at login**: Select Small (2 CPU) or Medium (4 CPU) notebook
4. **Isolated Hub**: JupyterHub won't compete with user pods for resources
5. **Cost savings**: Scale-to-zero for user/worker nodes when idle
6. **Newer Kubernetes**: 1.34 vs 1.29

### Preserved Behavior
1. **Same Cognito login**: No credential changes needed
2. **Same S3 scratch bucket**: cadcat-tmp with user data preserved
3. **Same lifecycle hooks**: climakitae and cae-notebooks installed at startup
4. **Same idle timeouts**: 20 min kernel cull, 60 min server cull
5. **Same Dask flexibility**: 1-4 cores per worker choice preserved
6. **Same max cluster cores**: 20 cores per Dask cluster

### Changes to Adapt To
1. **Admin change**: bgaley@ → mark.koenig@, neil.schroeder@
2. **Namespace**: daskhub → jupyterhub (internal only)
3. **Profile selection**: New login screen with Small/Medium choice

---

## Appendix: Configuration File Locations

| Environment | Config Files |
|-------------|--------------|
| **cae-jupyterhub** | `eks/cluster.yaml`, `daskhub.yaml`, `eks/storageclass.yaml` |
| **cae (tofu_era)** | `environments/cae/terraform.tfvars`, `environments/cae/secrets.yaml` |
| **englacial (tofu_era)** | `environments/englacial/terraform.tfvars`, `environments/englacial/secrets.yaml` |
| **cae-dev (tofu_era)** | `environments/cae-dev/terraform.tfvars`, `environments/cae-dev/secrets.yaml` |

---

## Appendix B: Availability Zone Selection - In-Depth Analysis

This section provides detailed analysis of the availability zone configuration differences between environments, including cost, stability, and availability trade-offs.

### Overview of AZ Strategies

| Environment | Main/System Nodes | User Nodes | Dask Workers |
|-------------|-------------------|------------|--------------|
| **cae-jupyterhub** | Single AZ (us-west-2a) | Single AZ (us-west-2a) | Single AZ (us-west-2a) |
| **cae (tofu_era)** | Single AZ (pin_main_nodes_single_az=true) | Single AZ (pin_user_nodes_single_az=true) | Single AZ |
| **englacial** | Multi-AZ (auto) | Multi-AZ (auto) | Multi-AZ (auto) |

### Why AZ Selection Matters

#### 1. EBS Volume Zone Affinity

**The Problem**: EBS volumes are zone-specific. A PersistentVolume created in `us-west-2a` can only attach to nodes in `us-west-2a`.

**Impact on JupyterHub**:
- User home directories are stored on EBS PersistentVolumes
- When a user's pod starts, it must run in the same AZ as their PV
- If no nodes exist in that AZ, the pod cannot start

**Configuration Example**:
```hcl
# cae terraform.tfvars
pin_user_nodes_single_az = true   # Forces all user nodes to us-west-2a
```

This ensures:
- All user PVs are created in us-west-2a
- All user pods run in us-west-2a
- Scale-up always provisions in the correct zone

#### 2. Multi-AZ vs Single-AZ Trade-offs

##### Multi-AZ (Spread Across Zones)

**Pros**:
- **High Availability**: Zone failure doesn't take down the cluster
- **Spot Instance Availability**: More capacity pools = better spot pricing
- **AWS Best Practice**: Recommended for production workloads

**Cons**:
- **PVC Affinity Issues**: Users may get volumes in different zones
- **Cross-AZ Data Transfer**: ~$0.01/GB for traffic between zones
- **Scheduling Complexity**: Pods may not find nodes in their PV's zone

##### Single-AZ (All Nodes in One Zone)

**Pros**:
- **PVC Simplicity**: All volumes and pods in same zone
- **No Cross-AZ Costs**: All traffic stays within zone
- **Predictable Scaling**: Autoscaler always provisions in correct zone

**Cons**:
- **Zone Failure Risk**: Single point of failure
- **Limited Spot Pool**: Fewer instance types available
- **Capacity Constraints**: Zone may run out of instances

### Environment-Specific Strategies

#### cae-jupyterhub (Legacy)

```yaml
# cluster.yaml
availabilityZones: ["us-west-2a", "us-west-2b"]
# But main2 nodegroup only in us-west-2a
```

**Strategy**: Although VPC spans two AZs, all workloads run in us-west-2a.

**Reasoning**:
- Historical simplicity
- All PVs in single zone
- Works but not fault-tolerant

#### cae (tofu_era)

```hcl
# terraform.tfvars
pin_main_nodes_single_az = true   # All nodes in single AZ
pin_user_nodes_single_az = true   # User nodes pinned to us-west-2a
```

**Strategy**: All single-AZ (matches cae-jupyterhub behavior).

- **System nodes (Hub, proxy)**: Single-AZ
- **User nodes**: Single-AZ for PVC affinity
- **Dask workers**: Single-AZ

**Reasoning**:
- With user PVs bound to a single AZ, Hub HA provides no real benefit
- If the AZ is down, users can't spawn regardless of where Hub runs
- Simpler, more honest about failure modes
- Matches existing cae-jupyterhub behavior

#### englacial

```hcl
# terraform.tfvars
pin_main_nodes_single_az = false
pin_user_nodes_single_az = false  # No pinning, full multi-AZ
```

**Strategy**: Full multi-AZ for maximum availability.

**Reasoning**:
- Research/testing workload
- Users don't have persistent data requirements
- Values availability over PVC simplicity

### Cost Analysis

#### Cross-AZ Data Transfer Costs

| Scenario | Cost per GB |
|----------|-------------|
| Same AZ traffic | $0.00 |
| Cross-AZ traffic (within VPC) | ~$0.01 |
| NAT Gateway (per GB) | $0.045 |

**Example monthly cost (assuming 1 TB cross-AZ)**:
- Multi-AZ user nodes: ~$10/month additional
- Single-AZ user nodes: $0 additional

#### Spot Instance Savings

| AZ Strategy | Spot Savings Potential | Reason |
|-------------|------------------------|--------|
| Single-AZ | 50-70% | Limited pools may hit capacity |
| Multi-AZ | 60-80% | More pools, better prices |

**Example**: m5.large in us-west-2
- us-west-2a spot: $0.035/hr (65% savings)
- us-west-2b spot: $0.032/hr (68% savings)
- us-west-2d spot: $0.029/hr (71% savings)
- Multi-AZ access: Best available price

### Stability Considerations

#### User Experience Impact

| Scenario | Single-AZ User Nodes | Multi-AZ User Nodes |
|----------|----------------------|---------------------|
| User login after idle | ✓ Fast, predictable | ⚠ May wait for node in correct AZ |
| PV already exists | ✓ Node guaranteed in zone | ⚠ Must wait for specific AZ node |
| New user first login | ✓ Any zone works | ✓ Any zone works |
| Zone capacity full | ❌ User blocked | ⚠ Still blocked if PV in that zone |

#### System Stability Impact

| Scenario | Single-AZ System | Multi-AZ System |
|----------|------------------|-----------------|
| Zone outage | ❌ Total cluster down | ✓ Hub failover possible |
| Zone degradation | ⚠ All users affected | ✓ Partial impact |
| Maintenance event | ⚠ Potential disruption | ✓ Rolling update possible |

### Recommended Configurations

#### Production (cae)

```hcl
# Best for: User-facing production with persistent home directories on EBS
pin_main_nodes_single_az = true   # All nodes in single AZ
pin_user_nodes_single_az = true   # PVC reliability for users
```

**Rationale**: With EBS-backed user PVs in a single AZ, Hub multi-AZ provides no benefit - if the AZ is down, users can't spawn anyway. Single-AZ is simpler and matches cae-jupyterhub.

#### Development/Testing (cae-dev)

```hcl
# Mirrors production for realistic testing
pin_main_nodes_single_az = true
pin_user_nodes_single_az = true
```

**Rationale**: Test the same configuration that will run in production.

#### Research/HPC (englacial)

```hcl
# Best for: Ephemeral workloads, no persistent user data
pin_main_nodes_single_az = false
pin_user_nodes_single_az = false  # Full HA
```

**Rationale**: No persistent data concerns; maximize availability and spot savings.

### Monitoring AZ Distribution

To see current node distribution:

```bash
# View nodes by zone
kubectl get nodes -L topology.kubernetes.io/zone

# View PVs by zone
kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[?(@.key=="topology.kubernetes.io/zone")].values[0]}{"\n"}{end}'
```

### Migration Considerations

When migrating from cae-jupyterhub to cae (tofu_era):

1. **Existing PVs**: If users have data in us-west-2a, keep pinning to us-west-2a
2. **Cross-AZ migration**: Would require manual PV snapshot and restore
3. **S3 bucket (cadcat-tmp)**: S3 is region-wide, no zone considerations

**Recommendation**: Maintain single-AZ for user nodes to preserve existing user data access patterns.

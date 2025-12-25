# Environment Sync Strategy

This document outlines a strategy for synchronizing configuration changes between testing and production environments while preserving environment-specific settings.

## Table of Contents
1. [The Challenge](#the-challenge)
2. [Solution Architecture](#solution-architecture)
3. [Configuration Layers](#configuration-layers)
4. [Sync Commands](#sync-commands)
5. [Implementation](#implementation)
6. [Usage Examples](#usage-examples)

---

## The Challenge

We need to synchronize changes between environments while:
- **Preserving production-specific settings**: Static IPs, high availability configs, domain names
- **Preserving test-specific settings**: Reduced resources, cost optimization, test domains
- **Syncing feature changes**: New modules, updated configurations, architectural changes

### What We CAN'T Do

```bash
# This would destroy production settings!
cp environments/dev/terraform.tfvars environments/prod/terraform.tfvars
```

### What We NEED

A way to:
1. Extract **feature changes** from one environment
2. Apply them to another environment
3. Preserve **environment-specific overrides**

---

## Solution Architecture

### Three-Layer Configuration Model

```
┌─────────────────────────────────────────────────────────────────┐
│                     terraform.tfvars                             │
│                 (environment-specific settings)                  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │               shared-features.tfvars                         │ │
│  │           (features that sync across envs)                   │ │
│  │                                                              │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │              variables.tf (defaults)                     │ │ │
│  │  │          (base defaults for all environments)            │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Layer Definitions

**Layer 1: Base Defaults (`variables.tf`)**
- Default values that work for any environment
- Changed infrequently
- Version-controlled with the module

**Layer 2: Shared Features (`shared-features.tfvars`)**
- Features that should sync across environments
- Dask worker configuration
- Resource limits
- Idle timeouts
- Container images

**Layer 3: Environment Overrides (`terraform.tfvars`)**
- Environment-specific settings that NEVER sync
- Domain names, IPs
- HA settings (replica counts, multi-AZ)
- Cost settings (instance types, node counts)
- Environment tags

---

## Configuration Layers

### Layer 2: Shared Features File

Create `environments/shared-features.tfvars`:

```hcl
# Shared Features Configuration
# These settings sync across all environments
# Last synced: YYYY-MM-DD from environment: XXX

# =============================================================================
# Container Image Configuration
# =============================================================================
singleuser_image_name = "pangeo/pangeo-notebook"
singleuser_image_tag  = "2025.01.10"

# =============================================================================
# Dask Gateway Configuration
# =============================================================================
dask_worker_cores_max  = 1     # 1 core per worker (optimized for CPU-bound)
dask_worker_memory_max = 3     # 3GB per worker
dask_cluster_max_cores = 200   # Max 200 cores per cluster

# =============================================================================
# Idle Timeouts
# =============================================================================
kernel_cull_timeout = 1200  # 20 minutes
server_cull_timeout = 3600  # 60 minutes

# =============================================================================
# Feature Flags
# =============================================================================
enable_profile_selection = true   # User selects instance size at login
use_three_node_groups    = true   # 3-node architecture (system, user, worker)
enable_lambda_invoke     = true   # Lambda for xagg processing

# =============================================================================
# Authentication
# =============================================================================
github_enabled = true
# Note: github_org_whitelist is environment-specific
```

### Layer 3: Environment Overrides

Each `environments/<env>/terraform.tfvars` should be structured:

```hcl
# =============================================================================
# ENVIRONMENT-SPECIFIC SETTINGS (DO NOT SYNC)
# =============================================================================

# Core Settings - NEVER SYNC
environment  = "prod"
region       = "us-west-2"
cluster_name = "jupyterhub"
domain_name  = "hub.production.example.com"
admin_email  = "admin@example.com"
owner_email  = "platform@example.com"
cost_center  = "platform"

# Network - Environment Specific
vpc_cidr           = "10.1.0.0/16"
enable_nat_gateway = true
single_nat_gateway = false  # Multi-AZ for HA in prod

# Node Sizing - Environment Specific
system_node_instance_types = ["r5.large"]
system_node_min_size       = 1
system_node_max_size       = 1

user_node_instance_types = ["r5.large", "r5.xlarge"]
user_node_min_size       = 0
user_node_max_size       = 20  # Higher for prod

dask_node_instance_types = [
  "m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge",
  "m5a.large", "m5a.xlarge", "m5a.2xlarge", "m5a.4xlarge"
]
dask_node_max_size = 100

# Safety - Environment Specific
deletion_protection = true   # Prod only
force_destroy_s3    = false  # Prod only

# =============================================================================
# SYNCED FEATURES (from shared-features.tfvars)
# Last synced: 2024-12-25 from: englacial
# =============================================================================

# Container Images
singleuser_image_name = "pangeo/pangeo-notebook"
singleuser_image_tag  = "2025.01.10"

# Dask Configuration
dask_worker_cores_max  = 1
dask_worker_memory_max = 3
dask_cluster_max_cores = 200

# Timeouts
kernel_cull_timeout = 1200
server_cull_timeout = 3600

# Features
enable_profile_selection = true
use_three_node_groups    = true
enable_lambda_invoke     = true
github_enabled           = true
```

---

## Sync Commands

### New Makefile Targets

Add these targets to the Makefile:

```makefile
##@ Environment Sync

# Variables for sync operations
SYNC_SOURCE ?= englacial
SYNC_TARGET ?= dev
SHARED_FEATURES := environments/shared-features.tfvars

# Define which variables are "syncable" (features) vs "environment-specific"
SYNCABLE_VARS := singleuser_image_name singleuser_image_tag \
                 dask_worker_cores_max dask_worker_memory_max dask_cluster_max_cores \
                 kernel_cull_timeout server_cull_timeout \
                 enable_profile_selection use_three_node_groups enable_lambda_invoke \
                 github_enabled

ENV_SPECIFIC_VARS := environment region cluster_name domain_name admin_email owner_email \
                     cost_center vpc_cidr enable_nat_gateway single_nat_gateway \
                     deletion_protection force_destroy_s3 skip_final_snapshot \
                     system_node_instance_types system_node_min_size system_node_max_size \
                     user_node_instance_types user_node_min_size user_node_max_size \
                     dask_node_instance_types dask_node_min_size dask_node_max_size \
                     kubernetes_version enable_acm acm_enable_wildcard acm_auto_validate \
                     github_org_whitelist pin_main_nodes_single_az pin_user_nodes_single_az

sync-features-from: ## Extract syncable features from source env (SYNC_SOURCE=env)
	@echo -e "$(GREEN)Extracting syncable features from $(SYNC_SOURCE)...$(NC)"
	@SOURCE_FILE="environments/$(SYNC_SOURCE)/terraform.tfvars"; \
	if [ ! -f "$$SOURCE_FILE" ]; then \
		echo -e "$(RED)Error: $$SOURCE_FILE not found$(NC)"; \
		exit 1; \
	fi; \
	echo "# Shared Features Configuration" > $(SHARED_FEATURES); \
	echo "# Extracted from: $(SYNC_SOURCE)" >> $(SHARED_FEATURES); \
	echo "# Date: $$(date +%Y-%m-%d)" >> $(SHARED_FEATURES); \
	echo "" >> $(SHARED_FEATURES); \
	for var in $(SYNCABLE_VARS); do \
		VALUE=$$(grep "^$$var " "$$SOURCE_FILE" | head -1); \
		if [ -n "$$VALUE" ]; then \
			echo "$$VALUE" >> $(SHARED_FEATURES); \
		fi; \
	done
	@echo -e "$(GREEN)Features extracted to $(SHARED_FEATURES)$(NC)"
	@echo "Review the file and then run: make sync-features-to SYNC_TARGET=<env>"

sync-features-to: ## Apply shared features to target env (SYNC_TARGET=env)
	@echo -e "$(YELLOW)Syncing features to $(SYNC_TARGET)...$(NC)"
	@TARGET_FILE="environments/$(SYNC_TARGET)/terraform.tfvars"; \
	BACKUP_FILE="environments/$(SYNC_TARGET)/terraform.tfvars.bak"; \
	if [ ! -f "$$TARGET_FILE" ]; then \
		echo -e "$(RED)Error: $$TARGET_FILE not found$(NC)"; \
		exit 1; \
	fi; \
	if [ ! -f "$(SHARED_FEATURES)" ]; then \
		echo -e "$(RED)Error: $(SHARED_FEATURES) not found. Run sync-features-from first$(NC)"; \
		exit 1; \
	fi; \
	cp "$$TARGET_FILE" "$$BACKUP_FILE"; \
	echo "Backup created: $$BACKUP_FILE"; \
	for var in $(SYNCABLE_VARS); do \
		NEW_VALUE=$$(grep "^$$var " "$(SHARED_FEATURES)" | head -1); \
		if [ -n "$$NEW_VALUE" ]; then \
			if grep -q "^$$var " "$$TARGET_FILE"; then \
				sed -i "s|^$$var .*|$$NEW_VALUE|" "$$TARGET_FILE"; \
			else \
				echo "$$NEW_VALUE" >> "$$TARGET_FILE"; \
			fi; \
		fi; \
	done; \
	echo -e "$(GREEN)Features synced to $$TARGET_FILE$(NC)"; \
	echo "Review changes with: diff $$BACKUP_FILE $$TARGET_FILE"

sync-diff: ## Show differences between two environments
	@echo -e "$(GREEN)Comparing $(SYNC_SOURCE) → $(SYNC_TARGET)$(NC)"
	@echo ""
	@echo "=== SYNCABLE FEATURES ==="
	@for var in $(SYNCABLE_VARS); do \
		SRC=$$(grep "^$$var " "environments/$(SYNC_SOURCE)/terraform.tfvars" | head -1 | sed 's/.*= //'); \
		TGT=$$(grep "^$$var " "environments/$(SYNC_TARGET)/terraform.tfvars" | head -1 | sed 's/.*= //'); \
		if [ "$$SRC" != "$$TGT" ]; then \
			echo -e "$(YELLOW)$$var$(NC)"; \
			echo "  $(SYNC_SOURCE): $$SRC"; \
			echo "  $(SYNC_TARGET): $$TGT"; \
		fi; \
	done
	@echo ""
	@echo "=== ENVIRONMENT-SPECIFIC (not synced) ==="
	@for var in $(ENV_SPECIFIC_VARS); do \
		SRC=$$(grep "^$$var " "environments/$(SYNC_SOURCE)/terraform.tfvars" | head -1 | sed 's/.*= //'); \
		TGT=$$(grep "^$$var " "environments/$(SYNC_TARGET)/terraform.tfvars" | head -1 | sed 's/.*= //'); \
		if [ "$$SRC" != "$$TGT" ]; then \
			echo "$$var: $$SRC → $$TGT"; \
		fi; \
	done

sync-promote: ## Promote features from test to prod (SYNC_SOURCE=test → SYNC_TARGET=prod)
	@echo -e "$(YELLOW)Promoting features from $(SYNC_SOURCE) to $(SYNC_TARGET)$(NC)"
	@echo "This will:"
	@echo "  1. Extract features from $(SYNC_SOURCE)"
	@echo "  2. Apply them to $(SYNC_TARGET)"
	@echo "  3. Show the diff for review"
	@echo ""
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read dummy
	$(MAKE) sync-features-from SYNC_SOURCE=$(SYNC_SOURCE)
	$(MAKE) sync-features-to SYNC_TARGET=$(SYNC_TARGET)
	$(MAKE) sync-diff SYNC_SOURCE=$(SYNC_SOURCE) SYNC_TARGET=$(SYNC_TARGET)

sync-backport: ## Backport features from prod to test (SYNC_SOURCE=prod → SYNC_TARGET=test)
	@echo -e "$(YELLOW)Backporting features from $(SYNC_SOURCE) to $(SYNC_TARGET)$(NC)"
	$(MAKE) sync-promote SYNC_SOURCE=$(SYNC_SOURCE) SYNC_TARGET=$(SYNC_TARGET)
```

---

## Implementation

### Step 1: Create Shared Features Template

Create `environments/shared-features.tfvars.template`:

```hcl
# Shared Features Configuration Template
# Copy this to shared-features.tfvars and customize

# Container Images
singleuser_image_name = "pangeo/pangeo-notebook"
singleuser_image_tag  = "2025.01.10"

# Dask Configuration
dask_worker_cores_max  = 1
dask_worker_memory_max = 3
dask_cluster_max_cores = 200

# Timeouts
kernel_cull_timeout = 1200
server_cull_timeout = 3600

# Features
enable_profile_selection = true
use_three_node_groups    = true
enable_lambda_invoke     = true
github_enabled           = true
```

### Step 2: Add Sync Targets to Makefile

Add the Makefile targets shown above to your existing Makefile.

### Step 3: Update .gitignore

```gitignore
# Backup files from sync operations
*.bak

# Shared features file (generated, but can be committed for reference)
# environments/shared-features.tfvars
```

---

## Usage Examples

### Example 1: Promote Test Feature to Production

You've tested a new Dask configuration in `englacial` and want to apply it to `prod`:

```bash
# Step 1: Extract features from englacial
make sync-features-from SYNC_SOURCE=englacial

# Step 2: Review the extracted features
cat environments/shared-features.tfvars

# Step 3: Apply to production
make sync-features-to SYNC_TARGET=prod

# Step 4: Review the diff
diff environments/prod/terraform.tfvars.bak environments/prod/terraform.tfvars

# Step 5: Commit the changes
git add environments/prod/terraform.tfvars
git commit -m "Sync Dask config from englacial to prod"
```

### Example 2: Compare Two Environments

```bash
# See all differences between englacial and prod
make sync-diff SYNC_SOURCE=englacial SYNC_TARGET=prod
```

Output:
```
Comparing englacial → prod

=== SYNCABLE FEATURES ===
dask_cluster_max_cores
  englacial: 200
  prod: 40

=== ENVIRONMENT-SPECIFIC (not synced) ===
domain_name: "hub.englacial.org" → "hub.production.example.com"
vpc_cidr: "10.4.0.0/16" → "10.1.0.0/16"
dask_node_max_size: 100 → 50
deletion_protection: false → true
```

### Example 3: Backport Production Settings to Dev

Production has a stable configuration you want to use as the new baseline for development:

```bash
make sync-backport SYNC_SOURCE=prod SYNC_TARGET=dev
```

### Example 4: One-Step Promote

```bash
# Promote from englacial (test) to prod (production)
make sync-promote SYNC_SOURCE=englacial SYNC_TARGET=prod
```

---

## Advanced: Partial Sync

For syncing only specific variables, you can extend the Makefile:

```makefile
# Sync only container image settings
sync-images:
	@echo "Syncing container images from $(SYNC_SOURCE) to $(SYNC_TARGET)"
	@for var in singleuser_image_name singleuser_image_tag; do \
		NEW_VALUE=$$(grep "^$$var " "environments/$(SYNC_SOURCE)/terraform.tfvars"); \
		sed -i "s|^$$var .*|$$NEW_VALUE|" "environments/$(SYNC_TARGET)/terraform.tfvars"; \
	done

# Sync only Dask configuration
sync-dask:
	@echo "Syncing Dask config from $(SYNC_SOURCE) to $(SYNC_TARGET)"
	@for var in dask_worker_cores_max dask_worker_memory_max dask_cluster_max_cores; do \
		NEW_VALUE=$$(grep "^$$var " "environments/$(SYNC_SOURCE)/terraform.tfvars"); \
		sed -i "s|^$$var .*|$$NEW_VALUE|" "environments/$(SYNC_TARGET)/terraform.tfvars"; \
	done

# Sync only timeout settings
sync-timeouts:
	@echo "Syncing timeout settings from $(SYNC_SOURCE) to $(SYNC_TARGET)"
	@for var in kernel_cull_timeout server_cull_timeout; do \
		NEW_VALUE=$$(grep "^$$var " "environments/$(SYNC_SOURCE)/terraform.tfvars"); \
		sed -i "s|^$$var .*|$$NEW_VALUE|" "environments/$(SYNC_TARGET)/terraform.tfvars"; \
	done
```

---

## Safety Considerations

### 1. Always Review Diffs

Never blindly apply synced features. Always review:
```bash
diff environments/prod/terraform.tfvars.bak environments/prod/terraform.tfvars
```

### 2. Test in Dev First

When syncing from production to development (backporting), test the sync process:
```bash
make sync-backport SYNC_SOURCE=prod SYNC_TARGET=dev
make plan ENVIRONMENT=dev
# Review plan carefully
```

### 3. Keep Backups

The sync commands automatically create `.bak` files. Keep these until you've verified the sync worked.

### 4. Commit Atomically

When promoting features, commit the changes to both environments in the same commit:
```bash
git add environments/englacial/terraform.tfvars environments/prod/terraform.tfvars
git commit -m "Promote Dask config from englacial to prod"
```

### 5. Use PR Reviews

For production changes, always go through a PR:
1. Create branch: `git checkout -b sync-dask-config`
2. Run sync: `make sync-promote SYNC_SOURCE=englacial SYNC_TARGET=prod`
3. Commit and push
4. Create PR for review
5. Run `make plan ENVIRONMENT=prod` in CI
6. Merge after approval

---

## Summary

| Command | Direction | Use Case |
|---------|-----------|----------|
| `make sync-features-from SYNC_SOURCE=env` | Extract from env | Capture current config |
| `make sync-features-to SYNC_TARGET=env` | Apply to env | Deploy captured config |
| `make sync-diff` | Compare | See what differs |
| `make sync-promote` | Source → Target | Test to Prod |
| `make sync-backport` | Source → Target | Prod to Test |
| `make sync-images` | Source → Target | Just container images |
| `make sync-dask` | Source → Target | Just Dask config |

This strategy ensures:
- Features can flow between environments
- Production settings are never accidentally overwritten
- Changes are auditable and reversible
- The sync process is repeatable and scriptable

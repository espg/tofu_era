#!/usr/bin/env bash
# Verify that tofu destroy actually removed everything in AWS.
#
# Tofu can report a successful destroy while leaving resources orphaned -- for
# instance if `tofu state rm` was used to unblock a stuck destroy, the state
# goes empty but the cloud resources keep billing. This script asks AWS
# directly: are any resources still present for this environment?
#
# Exits non-zero on any orphan found. Wire this in as the final step of
# `make destroy` and the GH Actions Destroy workflow so future regressions
# surface in CI on the same day, not on the next billing cycle.
#
# Resources INTENTIONALLY out of scope (managed out-of-band, not via tofu state):
#   - alias/sops-jupyterhub-<env>  KMS key created by `make check-sops-config`
#   - ECR pull-through cache rule `ghcr` + `ecr-pullthroughcache/ghcr` secret
#     (the main.tf null_resource calls these out as account-wide, create-once)
#
# Usage: scripts/verify-clean-teardown.sh <environment> <region>

set -euo pipefail

ENV="${1:?usage: $0 <environment> <region>}"
REGION="${2:?usage: $0 <environment> <region>}"

TFVARS="environments/${ENV}/terraform.tfvars"
CLUSTER_BASE=$(awk -F'"' '/^cluster_name/ {print $2}' "$TFVARS" 2>/dev/null || echo "jupyterhub")
CLUSTER_BASE=${CLUSTER_BASE:-jupyterhub}
CLUSTER="${CLUSTER_BASE}-${ENV}"

echo "[verify] auditing AWS for residual resources of env=$ENV (cluster prefix: $CLUSTER)"
fail=0

# 1. Anything still tagged with Application=jupyterhub + Environment=<env>.
#    This is the canonical signal -- main.tf:78-84 applies these tags to
#    every tofu-managed resource via the provider default_tags block.
echo "[verify] tagged resources (Application=jupyterhub, Environment=$ENV) -- ADVISORY"
# ADVISORY ONLY -- this does NOT fail the job. Two reasons the tag index is
# unreliable as a hard gate:
#   1. resourcegroupstaggingapi is eventually-consistent and can keep listing
#      NAT/VPC/subnet/endpoint ARNs for up to ~an hour AFTER they are actually
#      deleted (observed: NAT + VPC endpoint still listed 1h post-delete while
#      describe-* returns NotFound). A settle window can't outlast that.
#   2. KMS keys tagged for this env are never orphans -- either the permanent
#      out-of-band SOPS key (survives destroy by design) or an EKS key in its
#      pending-deletion window (scheduled, not billing).
# The AUTHORITATIVE pass/fail is the name-based describe checks below, which
# query live resource state directly and are immune to tag-index lag.
tagged=$(aws resourcegroupstaggingapi get-resources --region "$REGION" \
  --tag-filters "Key=Application,Values=jupyterhub" "Key=Environment,Values=$ENV" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^arn:aws:kms:' || true)
if [ -n "$tagged" ]; then
  echo "[verify] NOTE: tag index still lists the following (likely deletion lag;"
  echo "[verify]       cross-check with 'aws <svc> describe-*' if unsure -- not a failure):"
  printf '         %s\n' $tagged
fi

# 2. Backstop checks by Name tag for the resource types most commonly orphaned
#    during partial destroys (the Jan 2026 incident left exactly these).
#    Resources here may have lost their Application/Environment tags during
#    `tofu state rm`, so we also look them up by name.
echo "[verify] NAT gateways named ${CLUSTER}-*"
nats=$(aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=tag:Name,Values=${CLUSTER}-nat,${CLUSTER}-nat-*" \
  --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text 2>/dev/null || true)
if [ -n "$nats" ]; then echo "[verify] FAIL NAT gateways: $nats" >&2; fail=1; fi

echo "[verify] VPCs named ${CLUSTER}-vpc"
vpcs=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=tag:Name,Values=${CLUSTER}-vpc" \
  --query 'Vpcs[].VpcId' --output text 2>/dev/null || true)
if [ -n "$vpcs" ]; then echo "[verify] FAIL VPCs: $vpcs" >&2; fail=1; fi

echo "[verify] EIPs named ${CLUSTER}-nat*"
# describe-addresses does not support tag filters, so filter client-side.
eips=$(aws ec2 describe-addresses --region "$REGION" \
  --query "Addresses[?Tags && length(Tags[?Key=='Name' && starts_with(Value, '${CLUSTER}-nat')]) > \`0\`].AllocationId" \
  --output text 2>/dev/null || true)
if [ -n "$eips" ]; then echo "[verify] FAIL EIPs: $eips" >&2; fail=1; fi

echo "[verify] EKS clusters named $CLUSTER"
if aws eks describe-cluster --region "$REGION" --name "$CLUSTER" >/dev/null 2>&1; then
  echo "[verify] FAIL EKS cluster $CLUSTER still exists" >&2
  fail=1
fi

echo "[verify] LoadBalancers in VPCs named ${CLUSTER}-vpc"
lbs=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[?contains(LoadBalancerName, '${CLUSTER_BASE}')].LoadBalancerArn" \
  --output text 2>/dev/null || true)
if [ -n "$lbs" ]; then echo "[verify] FAIL load balancers: $lbs" >&2; fail=1; fi

if [ "$fail" -ne 0 ]; then
  cat >&2 <<EOF

[verify] FAIL: AWS resources remain for environment '$ENV' after tofu destroy.
[verify] The tofu state may be empty but the cloud is not -- this is the
[verify] orphaned-resource failure mode. Investigate with:
[verify]   make show ENVIRONMENT=$ENV     # show tofu state
[verify]   aws resourcegroupstaggingapi get-resources \\
[verify]     --tag-filters Key=Environment,Values=$ENV --region $REGION
[verify] Resolve before re-running destroy.
EOF
  exit 1
fi

echo "[verify] OK: no jupyterhub/$ENV resources remain in $REGION"
echo "[verify] (Account-wide ECR pull-through cache + SOPS KMS key intentionally not checked)"

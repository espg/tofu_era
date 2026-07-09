#!/usr/bin/env bash
# Drain Kubernetes-managed AWS load balancers before tofu touches networking.
#
# Without this step, the AWS Load Balancer Controller's ELB/NLB ENIs remain in
# the private subnets when the helm release is destroyed. Those ENIs block
# subnet -> VPC delete, tofu destroy errors partway, and if an operator runs
# `tofu state rm` to clear the stuck resources the destroy "completes" with
# state empty but NAT gateways, VPCs, EIPs, etc. still billing in AWS.
# This was the root cause of the Jan 2026 cae-dev/cae-testing orphan incident.
#
# Usage: scripts/pre-destroy-drain.sh <environment> <region>
#   Reads cluster_name from environments/<env>/terraform.tfvars to support
#   per-env overrides (e.g. cae-testing uses cluster_name "jupyterhub-testing").

set -euo pipefail

ENV="${1:?usage: $0 <environment> <region>}"
REGION="${2:?usage: $0 <environment> <region>}"

TFVARS="environments/${ENV}/terraform.tfvars"
if [ ! -f "$TFVARS" ]; then
  echo "[drain] ERROR: tfvars file $TFVARS not found" >&2
  exit 1
fi

CLUSTER_BASE=$(awk -F'"' '/^cluster_name/ {print $2}' "$TFVARS")
CLUSTER_BASE=${CLUSTER_BASE:-jupyterhub}
CLUSTER="${CLUSTER_BASE}-${ENV}"

echo "[drain] target cluster: $CLUSTER (region: $REGION)"

# If the cluster is already gone (e.g. a prior partial destroy), skip k8s
# drain and go straight to waiting on ENI cleanup -- the controller may still
# have outstanding work even after the cluster delete returned.
if aws eks describe-cluster --region "$REGION" --name "$CLUSTER" >/dev/null 2>&1; then
  echo "[drain] configuring kubectl for $CLUSTER"
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null

  echo "[drain] deleting LoadBalancer Services cluster-wide"
  # jsonpath avoids needing jq; spec.type is not a supported field-selector.
  while read -r ns name; do
    [ -z "$ns" ] && continue
    echo "[drain]   svc/$name in $ns"
    kubectl delete svc "$name" -n "$ns" --wait=true --timeout=5m --ignore-not-found
  done < <(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace} {.metadata.name}{"\n"}{end}')

  echo "[drain] deleting Ingresses cluster-wide"
  kubectl delete ingress -A --all --wait=true --timeout=5m --ignore-not-found || true

  # Delete user PVCs so the gp3 StorageClass's reclaimPolicy=Delete actually runs
  # WHILE the EBS CSI controller is still alive. Otherwise tofu destroy tears the
  # cluster out from under the PVCs and the backing EBS volumes orphan -- billing
  # forever, with no data evacuation. Set KEEP_USER_VOLUMES=1 to skip (e.g. to
  # preserve homes for a manual reattach; see issue #6 / Option A).
  if [ "${KEEP_USER_VOLUMES:-0}" = "1" ]; then
    echo "[drain] KEEP_USER_VOLUMES=1 set; leaving PVCs/EBS volumes in place"
  else
    # Capture the EBS volume IDs backing current PVs BEFORE deleting anything,
    # so we can wait for their actual deletion afterward.
    VOL_IDS=$(kubectl get pv -o jsonpath='{range .items[?(@.spec.csi.driver=="ebs.csi.aws.com")]}{.spec.csi.volumeHandle}{"\n"}{end}' 2>/dev/null || true)

    echo "[drain] stopping singleuser servers so their PVCs can be released"
    kubectl delete pods -A -l component=singleuser-server --wait=true --timeout=3m --ignore-not-found || true

    echo "[drain] deleting PVCs cluster-wide (reclaimPolicy=Delete removes the EBS volumes)"
    kubectl delete pvc -A --all --wait=true --timeout=5m --ignore-not-found || true

    if [ -n "$VOL_IDS" ]; then
      echo "[drain] waiting for backing EBS volumes to delete (up to 10 min)"
      remaining=""
      for i in $(seq 1 60); do
        remaining=""
        for v in $VOL_IDS; do
          aws ec2 describe-volumes --region "$REGION" --volume-ids "$v" >/dev/null 2>&1 && remaining="$remaining $v"
        done
        if [ -z "$remaining" ]; then
          echo "[drain] all user EBS volumes deleted after $((i * 10))s"
          break
        fi
        echo "[drain] EBS volumes still deleting:$remaining ($((i * 10))/600s)"
        sleep 10
      done
      if [ -n "$remaining" ]; then
        echo "[drain] WARNING: EBS volumes did not delete within 10 min:$remaining" >&2
        echo "[drain] Proceeding with destroy anyway (cluster teardown saves the most cost)." >&2
        echo "[drain] verify-clean-teardown.sh will flag them; delete manually to avoid EBS charges." >&2
      fi
    fi
  fi
else
  echo "[drain] cluster $CLUSTER not found in EKS; skipping k8s drain"
fi

# Find the VPC for this env and wait for any AWS LB Controller-owned ENIs to
# clear. Without this wait, even a "successful" k8s delete can race the AWS
# API and leave ENIs that block subnet delete a minute later.
VPC=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=tag:Name,Values=${CLUSTER}-vpc" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")

if [ "$VPC" = "None" ] || [ -z "$VPC" ]; then
  echo "[drain] no VPC tagged Name=${CLUSTER}-vpc; nothing left to wait on"
  exit 0
fi

echo "[drain] waiting for ELB ENIs in $VPC to clear (up to 10 min)"
for i in $(seq 1 60); do
  remaining=$(aws ec2 describe-network-interfaces --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC" \
    --query 'length(NetworkInterfaces[?starts_with(Description, `ELB`) || contains(Description, `elasticloadbalancing`) || contains(Description, `AWS Load Balancer Controller`)])' \
    --output text)
  if [ "$remaining" = "0" ]; then
    echo "[drain] all LB ENIs cleared after $((i*10))s"
    exit 0
  fi
  echo "[drain] $remaining LB ENI(s) remain; sleeping 10s ($((i*10))/600s)"
  sleep 10
done

echo "[drain] ERROR: LB ENIs did not clear after 10 min; aborting to prevent orphan" >&2
echo "[drain] Investigate manually -- the AWS Load Balancer Controller may have crashed mid-cleanup," >&2
echo "[drain] or there may be Service/Ingress objects in non-helm namespaces." >&2
exit 1

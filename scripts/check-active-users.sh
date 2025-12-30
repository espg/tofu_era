#!/bin/bash
# check-active-users.sh
# Check which users currently have running notebook servers on JupyterHub
#
# Usage: ./check-active-users.sh [NAMESPACE]

set -e

NAMESPACE="${1:-daskhub}"

echo "=== Active JupyterHub Users ==="
echo "Namespace: $NAMESPACE"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Method 1: Check for running jupyter-* pods
echo "--- Running User Pods ---"
RUNNING_PODS=$(kubectl get pods -n $NAMESPACE -l component=singleuser-server -o json 2>/dev/null)

if [ "$(echo $RUNNING_PODS | jq '.items | length')" -eq 0 ]; then
    echo "No active user sessions."
else
    echo "$RUNNING_PODS" | jq -r '
        .items[] |
        "\(.metadata.name)\t\(.status.phase)\t\(.status.startTime)\t\(.spec.nodeName)"
    ' | column -t -s $'\t' -N "POD,STATUS,STARTED,NODE"

    echo ""
    echo "Total active users: $(echo $RUNNING_PODS | jq '.items | length')"
fi

echo ""

# Method 2: Check via JupyterHub API (if you have admin token)
# Uncomment if you have JUPYTERHUB_API_TOKEN set
# echo "--- Via JupyterHub API ---"
# HUB_SERVICE=$(kubectl get svc -n $NAMESPACE hub -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
# if [ -n "$HUB_SERVICE" ] && [ -n "$JUPYTERHUB_API_TOKEN" ]; then
#     curl -s -H "Authorization: token $JUPYTERHUB_API_TOKEN" \
#         "http://$HUB_SERVICE:8081/hub/api/users" | \
#         jq -r '.[] | select(.server != null) | .name'
# fi

# Method 3: Check PVCs that are currently bound (indicates user has logged in at least once)
echo "--- All User PVCs (ever logged in) ---"
kubectl get pvc -n $NAMESPACE -l component=singleuser-storage -o json 2>/dev/null | jq -r '
    .items[] |
    "\(.metadata.name)\t\(.status.phase)\t\(.spec.resources.requests.storage)"
' | column -t -s $'\t' -N "PVC,STATUS,SIZE" || echo "No user PVCs found"

# Alternative: If PVCs don't have labels, match by name pattern
if [ "$(kubectl get pvc -n $NAMESPACE -l component=singleuser-storage -o json 2>/dev/null | jq '.items | length')" -eq 0 ]; then
    echo ""
    echo "--- User PVCs (by name pattern claim-*) ---"
    kubectl get pvc -n $NAMESPACE -o json | jq -r '
        .items[] |
        select(.metadata.name | startswith("claim-")) |
        "\(.metadata.name)\t\(.status.phase)\t\(.spec.resources.requests.storage)"
    ' | column -t -s $'\t' -N "PVC,STATUS,SIZE"
fi

echo ""
echo "=== Summary ==="
ACTIVE_COUNT=$(kubectl get pods -n $NAMESPACE -l component=singleuser-server --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
TOTAL_PVCS=$(kubectl get pvc -n $NAMESPACE -o json | jq '[.items[] | select(.metadata.name | startswith("claim-"))] | length')

echo "Active sessions: $ACTIVE_COUNT"
echo "Total user PVCs: $TOTAL_PVCS"

if [ "$ACTIVE_COUNT" -gt 0 ]; then
    echo ""
    echo "⚠️  WARNING: Users are currently active. Migration will require stopping their sessions."
    exit 1
else
    echo ""
    echo "✓ No active users. Safe to proceed with migration."
    exit 0
fi

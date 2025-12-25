#!/bin/bash
# Kubecost UI Access Script
# Provides easy access to Kubecost cost monitoring UI

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="${ENVIRONMENT:-englacial}"
PORT="${PORT:-9090}"
NAMESPACE="kubecost"
SERVICE="kubecost-cost-analyzer"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -e|--environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    -p|--port)
      PORT="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Open Kubecost UI for JupyterHub cost monitoring"
      echo ""
      echo "Options:"
      echo "  -e, --environment ENV    Environment to connect to (default: englacial)"
      echo "                           Options: englacial, englacial-test, dasktest, etc."
      echo "  -p, --port PORT          Local port to use (default: 9090)"
      echo "  -h, --help               Show this help message"
      echo ""
      echo "Environment Variables:"
      echo "  ENVIRONMENT              Set default environment"
      echo ""
      echo "Examples:"
      echo "  $0                                    # Connect to englacial on port 9090"
      echo "  $0 -e englacial-test                 # Connect to englacial-test"
      echo "  $0 -p 8080                           # Use port 8080 instead"
      echo "  ENVIRONMENT=dasktest $0              # Use env var"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Run '$0 --help' for usage information"
      exit 1
      ;;
  esac
done

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${GREEN}Checking prerequisites...${NC}"

if ! command_exists kubectl; then
  echo -e "${RED}Error: kubectl not found${NC}"
  echo "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
  exit 1
fi

if ! command_exists aws; then
  echo -e "${RED}Error: aws CLI not found${NC}"
  echo "Install AWS CLI: https://aws.amazon.com/cli/"
  exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo -e "${RED}Error: AWS credentials not configured${NC}"
  echo "Configure AWS CLI: aws configure"
  exit 1
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}"
echo ""

# Update kubeconfig for the environment
echo -e "${GREEN}Configuring kubectl for environment: ${ENVIRONMENT}${NC}"

# Determine cluster name and region from backend config
BACKEND_CONFIG="environments/${ENVIRONMENT}/backend.tfvars"
if [ ! -f "$BACKEND_CONFIG" ]; then
  echo -e "${RED}Error: Environment '${ENVIRONMENT}' not found${NC}"
  echo "Available environments:"
  ls -1 environments/ | grep -v "\.tfvars\|\.yaml"
  exit 1
fi

# Extract region from backend config
REGION=$(grep '^region' "$BACKEND_CONFIG" | awk '{print $3}' | tr -d '"')
CLUSTER_NAME="jupyterhub-${ENVIRONMENT}"

echo -e "${YELLOW}Cluster: ${CLUSTER_NAME}${NC}"
echo -e "${YELLOW}Region: ${REGION}${NC}"
echo ""

# Update kubeconfig
echo -e "${GREEN}Updating kubeconfig...${NC}"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1

# Verify cluster access
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo -e "${RED}Error: Cannot access cluster${NC}"
  echo "Cluster may not exist or you may not have permissions"
  exit 1
fi

echo -e "${GREEN}✓ Connected to cluster${NC}"
echo ""

# Check if Kubecost is deployed
echo -e "${GREEN}Checking Kubecost deployment...${NC}"

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo -e "${RED}Error: Kubecost namespace not found${NC}"
  echo "Is Kubecost deployed? Check: kubectl get namespaces"
  exit 1
fi

if ! kubectl get svc -n "$NAMESPACE" "$SERVICE" >/dev/null 2>&1; then
  echo -e "${RED}Error: Kubecost service not found${NC}"
  echo "Is Kubecost deployed? Check: kubectl get pods -n $NAMESPACE"
  exit 1
fi

# Check if Kubecost pods are running
READY_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=cost-analyzer --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$READY_PODS" -eq 0 ]; then
  echo -e "${YELLOW}Warning: Kubecost pods may not be ready yet${NC}"
  echo "Current status:"
  kubectl get pods -n "$NAMESPACE" -l app=cost-analyzer
  echo ""
  echo "Continuing anyway (pod may still be starting)..."
  echo ""
fi

echo -e "${GREEN}✓ Kubecost is deployed${NC}"
echo ""

# Check if port is already in use
if lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo -e "${YELLOW}Warning: Port ${PORT} is already in use${NC}"
  echo "You may already have Kubecost UI open, or another service is using this port."
  echo ""
  read -p "Kill existing process on port ${PORT}? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    lsof -ti:${PORT} | xargs kill -9 2>/dev/null || true
    sleep 2
  else
    echo "Use a different port: $0 -p <PORT>"
    exit 1
  fi
fi

# Start port-forward in background
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  Kubecost UI - Starting                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Environment:${NC}     ${ENVIRONMENT}"
echo -e "${YELLOW}Cluster:${NC}         ${CLUSTER_NAME}"
echo -e "${YELLOW}Local URL:${NC}       http://localhost:${PORT}"
echo ""
echo -e "${GREEN}Starting port-forward...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

# Trap Ctrl+C to cleanup
cleanup() {
  echo ""
  echo -e "${GREEN}Stopping port-forward...${NC}"
  exit 0
}
trap cleanup INT TERM

# Start port-forward
kubectl port-forward -n "$NAMESPACE" "svc/${SERVICE}" "${PORT}:9090"

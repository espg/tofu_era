#!/bin/bash
# Unified Cost Report - Combines Kubecost (Kubernetes) + AWS Cost Explorer (Lambda/etc)
# Generates per-user cost breakdown across all infrastructure

set -eo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
ENVIRONMENT="${ENVIRONMENT:-englacial}"
DAYS="${DAYS:-7}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-table}"
OUTPUT_FILE=""
INCLUDE_LAMBDA="${INCLUDE_LAMBDA:-true}"
INCLUDE_STEP_FUNCTIONS="${INCLUDE_STEP_FUNCTIONS:-true}"
INCLUDE_S3="${INCLUDE_S3:-false}"
VERBOSE="${VERBOSE:-false}"

# Logging function
log() {
  if [ "$VERBOSE" = "true" ]; then
    echo -e "${BLUE}[DEBUG]${NC} $1" >&2
  fi
}

# Show help
show_help() {
  cat << EOF
Usage: $0 [OPTIONS]

Generate unified cost report combining Kubernetes (Kubecost) and AWS services

Options:
  -e, --environment ENV        Environment (default: englacial)
  -d, --days DAYS              Number of days (default: 7)
  -f, --format FORMAT          Output: table, csv, json (default: table)
  -o, --output FILE            Save to file
  --no-lambda                  Exclude Lambda costs
  --no-step-functions          Exclude Step Functions
  --include-s3                 Include S3 costs
  -v, --verbose                Verbose output
  -h, --help                   Show this help

Examples:
  $0                           # Last 7 days, table
  $0 -d 30 -f csv -o costs.csv # Last 30 days to CSV
  $0 --include-s3              # Include S3 costs
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -e|--environment) ENVIRONMENT="$2"; shift 2 ;;
    -d|--days) DAYS="$2"; shift 2 ;;
    -f|--format) OUTPUT_FORMAT="$2"; shift 2 ;;
    -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
    --no-lambda) INCLUDE_LAMBDA="false"; shift ;;
    --no-step-functions) INCLUDE_STEP_FUNCTIONS="false"; shift ;;
    --include-s3) INCLUDE_S3="true"; shift ;;
    -v|--verbose) VERBOSE="true"; shift ;;
    -h|--help) show_help; exit 0 ;;
    *) echo -e "${RED}Unknown: $1${NC}" >&2; exit 1 ;;
  esac
done

# Check prerequisites
check_prereqs() {
  for cmd in kubectl aws jq bc; do
    if ! command -v $cmd >/dev/null 2>&1; then
      echo -e "${RED}Error: $cmd not found${NC}" >&2
      [ "$cmd" = "bc" ] && echo "Install: sudo apt-get install bc (or brew install bc)" >&2
      exit 1
    fi
  done
}

# Configure kubectl
setup_kubectl() {
  local backend="environments/${ENVIRONMENT}/backend.tfvars"
  if [ ! -f "$backend" ]; then
    echo -e "${RED}Error: Environment '${ENVIRONMENT}' not found${NC}" >&2
    exit 1
  fi

  REGION=$(grep '^region' "$backend" | awk '{print $3}' | tr -d '"')
  CLUSTER_NAME="jupyterhub-${ENVIRONMENT}"

  log "Cluster: ${CLUSTER_NAME}, Region: ${REGION}"

  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1 || {
    echo -e "${RED}Error: Cannot configure kubectl${NC}" >&2
    exit 1
  }
}

# Get Kubecost data
get_kubecost_data() {
  log "Fetching Kubecost data for last ${DAYS} days..."

  local raw=$(kubectl exec -n kubecost deployment/kubecost-cost-analyzer -c cost-analyzer-frontend -- \
    curl -s "http://localhost:9090/model/allocation?window=${DAYS}d&aggregate=label:hub.jupyter.org/username" 2>/dev/null || echo '{"data":[]}')

  # Validate JSON
  if ! echo "$raw" | jq -e . >/dev/null 2>&1; then
    log "Warning: Invalid Kubecost response"
    echo '{"users":[],"infra":0}'
    return
  fi

  # Parse users and infrastructure
  local users=$(echo "$raw" | jq -c '[.data[]? | to_entries[] |
    select(.key != "" and .key != "__idle__" and .key != "__unallocated__") |
    {user: .key, k8s_cost: (.value.totalCost // 0)}]')

  local infra=$(echo "$raw" | jq -r '[.data[]? | to_entries[] |
    select(.key == "__idle__" or .key == "__unallocated__") |
    .value.totalCost // 0] | add // 0')

  echo "{\"users\":$users,\"infra\":$infra}"
}

# Get AWS Cost Explorer data
get_aws_costs() {
  local service=$1
  log "Fetching ${service} costs..."

  local end=$(date +%Y-%m-%d)
  local start=$(date -d "${DAYS} days ago" +%Y-%m-%d 2>/dev/null || date -v-${DAYS}d +%Y-%m-%d)

  local result=$(aws ce get-cost-and-usage \
    --time-period Start="${start}",End="${end}" \
    --granularity DAILY \
    --metrics UnblendedCost \
    --filter "{\"Dimensions\":{\"Key\":\"SERVICE\",\"Values\":[\"${service}\"]}}" \
    --group-by Type=TAG,Key=User \
    2>/dev/null || echo '{"ResultsByTime":[]}')

  # Parse and aggregate by user
  echo "$result" | jq -c '
    [.ResultsByTime[]?.Groups[]? |
     select(.Keys[0] != "" and (.Keys[0] | startswith("User$") | not)) |
     {user: (.Keys[0] | sub("User\\$"; "")), amount: (.Metrics.UnblendedCost.Amount | tonumber)}] |
    group_by(.user) |
    map({user: .[0].user, cost: (map(.amount) | add)})
  ' 2>/dev/null || echo '[]'
}

# Format as table
format_table() {
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║         Unified Cost Report - JupyterHub + AWS Services                ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  local env=$(echo "$COMBINED" | jq -r '.environment')
  local date=$(echo "$COMBINED" | jq -r '.report_date')
  local days=$(echo "$COMBINED" | jq -r '.days')
  local infra=$(echo "$COMBINED" | jq -r '.infrastructure_cost')

  echo -e "${YELLOW}Environment:${NC}     $env"
  echo -e "${YELLOW}Report Date:${NC}     $date"
  echo -e "${YELLOW}Period:${NC}          Last $days days"
  echo ""

  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  printf "%-30s %12s %12s %12s %12s %12s\n" "USER" "K8S/DASK" "LAMBDA" "STEP-FN" "S3" "TOTAL"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  echo "$COMBINED" | jq -r '.users[] | [.user, .k8s_cost, .lambda_cost, .sf_cost, .s3_cost, .total_cost] | @tsv' | \
  while IFS=$'\t' read -r user k8s lambda sf s3 total; do
    printf "%-30s \$%11.2f \$%11.2f \$%11.2f \$%11.2f \$%11.2f\n" \
      "${user:0:30}" "$k8s" "$lambda" "$sf" "$s3" "$total"
  done

  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  local total_k8s=$(echo "$COMBINED" | jq '[.users[].k8s_cost] | add // 0')
  local total_lambda=$(echo "$COMBINED" | jq '[.users[].lambda_cost] | add // 0')
  local total_sf=$(echo "$COMBINED" | jq '[.users[].sf_cost] | add // 0')
  local total_s3=$(echo "$COMBINED" | jq '[.users[].s3_cost] | add // 0')
  local total_all=$(echo "$COMBINED" | jq '[.users[].total_cost] | add // 0')

  printf "${YELLOW}%-30s \$%11.2f \$%11.2f \$%11.2f \$%11.2f \$%11.2f${NC}\n" \
    "TOTAL (users)" "$total_k8s" "$total_lambda" "$total_sf" "$total_s3" "$total_all"
  printf "${YELLOW}%-30s \$%11.2f %12s %12s %12s \$%11.2f${NC}\n" \
    "Infrastructure (shared)" "$infra" "-" "-" "-" "$infra"

  local grand=$(echo "$total_all + $infra" | bc)
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  printf "${GREEN}%-30s %12s %12s %12s %12s \$%11.2f${NC}\n" "GRAND TOTAL" "" "" "" "" "$grand"
  echo ""

  echo -e "${BLUE}Cost Breakdown:${NC}"
  echo "  • K8S/DASK:      JupyterHub pods + Dask workers (from Kubecost)"
  echo "  • LAMBDA:        AWS Lambda functions (from Cost Explorer)"
  echo "  • STEP-FN:       AWS Step Functions (from Cost Explorer)"
  echo "  • S3:            S3 storage (from Cost Explorer)"
  echo "  • Infrastructure: System nodes, EKS, NAT, ALB (shared)"
  echo ""

  local user_count=$(echo "$COMBINED" | jq '.users | length')
  if [ "$user_count" -eq 0 ]; then
    echo -e "${YELLOW}Note: No user costs found. Possible reasons:${NC}"
    echo "  - No users have logged in yet"
    echo "  - CUR data still populating (wait 24-48 hours after first deploy)"
    echo "  - Lambda functions not tagged with 'User' tag"
  fi
}

# Format as CSV
format_csv() {
  echo "User,K8s_Cost,Lambda_Cost,Step_Functions_Cost,S3_Cost,Total_Cost,Report_Date,Environment,Days"

  local date=$(echo "$COMBINED" | jq -r '.report_date')
  local env=$(echo "$COMBINED" | jq -r '.environment')
  local days=$(echo "$COMBINED" | jq -r '.days')

  echo "$COMBINED" | jq -r --arg d "$date" --arg e "$env" --arg dy "$days" '
    .users[] | [.user, .k8s_cost, .lambda_cost, .sf_cost, .s3_cost, .total_cost, $d, $e, $dy] | @csv
  '

  local infra=$(echo "$COMBINED" | jq -r '.infrastructure_cost')
  echo "\"Infrastructure (shared)\",$infra,0,0,0,$infra,$date,$env,$days"
}

# Format as JSON
format_json() {
  echo "$COMBINED" | jq '.'
}

#############################################################################
# MAIN EXECUTION
#############################################################################

echo -e "${GREEN}Generating unified cost report...${NC}" >&2

# Check prerequisites
check_prereqs

# Setup kubectl
setup_kubectl

# Get Kubecost data
KUBECOST_JSON=$(get_kubecost_data)
KUBECOST_USERS=$(echo "$KUBECOST_JSON" | jq -c '.users')
INFRA_COST=$(echo "$KUBECOST_JSON" | jq -r '.infra')

log "Kubecost: $(echo "$KUBECOST_USERS" | jq length) users, infra: \$$INFRA_COST"

# Calculate AWS Cost Explorer date range
END_DATE=$(date +%Y-%m-%d)
START_DATE=$(date -d "${DAYS} days ago" +%Y-%m-%d 2>/dev/null || date -v-${DAYS}d +%Y-%m-%d)

log "Date range: ${START_DATE} to ${END_DATE}"

# Get AWS costs
LAMBDA_DATA='[]'
SF_DATA='[]'
S3_DATA='[]'

[ "$INCLUDE_LAMBDA" = "true" ] && LAMBDA_DATA=$(get_aws_costs "AWS Lambda")
[ "$INCLUDE_STEP_FUNCTIONS" = "true" ] && SF_DATA=$(get_aws_costs "AWS Step Functions")
[ "$INCLUDE_S3" = "true" ] && S3_DATA=$(get_aws_costs "Amazon Simple Storage Service")

log "AWS data fetched"

# Combine all data sources
COMBINED=$(jq -n \
  --argjson k8s "$KUBECOST_USERS" \
  --argjson lambda "$LAMBDA_DATA" \
  --argjson sf "$SF_DATA" \
  --argjson s3 "$S3_DATA" \
  --arg infra "$INFRA_COST" \
  --arg env "$ENVIRONMENT" \
  --arg days "$DAYS" \
  --arg date "$(date '+%Y-%m-%d %H:%M:%S')" \
  '
  # Get all unique users from all sources
  ($k8s + $lambda + $sf + $s3 | map(.user) | unique) as $users |

  {
    report_date: $date,
    environment: $env,
    days: ($days | tonumber),
    infrastructure_cost: ($infra | tonumber),
    users: ($users | map(. as $user |
      {
        user: $user,
        k8s_cost: (($k8s[] | select(.user == $user).k8s_cost) // 0),
        lambda_cost: (($lambda[] | select(.user == $user).cost) // 0),
        sf_cost: (($sf[] | select(.user == $user).cost) // 0),
        s3_cost: (($s3[] | select(.user == $user).cost) // 0)
      } | . + {total_cost: (.k8s_cost + .lambda_cost + .sf_cost + .s3_cost)}
    ) | sort_by(-.total_cost))
  }
')

log "Data combined"

# Generate output
case "$OUTPUT_FORMAT" in
  table) OUTPUT=$(format_table) ;;
  csv) OUTPUT=$(format_csv) ;;
  json) OUTPUT=$(format_json) ;;
  *) echo -e "${RED}Invalid format: $OUTPUT_FORMAT${NC}" >&2; exit 1 ;;
esac

# Write output
if [ -n "$OUTPUT_FILE" ]; then
  echo "$OUTPUT" > "$OUTPUT_FILE"
  echo -e "${GREEN}✓ Report saved: $OUTPUT_FILE${NC}" >&2

  # Show summary
  USER_COUNT=$(echo "$COMBINED" | jq '.users | length')
  TOTAL_USER_COST=$(echo "$COMBINED" | jq '[.users[].total_cost] | add // 0')
  echo -e "${YELLOW}Summary:${NC} $USER_COUNT users, \$$TOTAL_USER_COST total (excluding infra)" >&2
else
  echo "$OUTPUT"
fi

# Terra JupyterHub - OpenTofu Makefile
# Automated deployment and management for JupyterHub on EKS using OpenTofu

SHELL := /bin/bash
.PHONY: help init plan apply destroy clean validate fmt lint cost-estimate backup restore scale-down scale-up status check-secrets

# Variables
# Support both ENV and ENVIRONMENT for convenience
ENV ?= dev
ENVIRONMENT ?= $(ENV)
REGION ?= us-west-2
CLUSTER_NAME ?= jupyterhub
AUTO_APPROVE ?= false

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# OpenTofu/Terraform backend config
BACKEND_CONFIG := environments/$(ENVIRONMENT)/backend.tfvars
TFVARS := environments/$(ENVIRONMENT)/terraform.tfvars
STATE_BUCKET := terraform-state-$(CLUSTER_NAME)-$(ENVIRONMENT)

# Check for OpenTofu, fall back to Terraform if not found
TERRAFORM_CMD := $(shell which tofu 2>/dev/null || which terraform 2>/dev/null)
ifeq ($(TERRAFORM_CMD),)
$(error Neither OpenTofu nor Terraform found in PATH. Please install OpenTofu: https://opentofu.org/docs/intro/install/)
endif

# Extract binary name for messages
TF_BINARY := $(shell basename $(TERRAFORM_CMD))

##@ General

help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	@echo ""
	@echo "Environment Variables:"
	@echo "  ENVIRONMENT    - Target environment (current: $(ENVIRONMENT))"
	@echo "  REGION        - AWS region (current: $(REGION))"
	@echo "  AUTO_APPROVE  - Skip approval prompts (current: $(AUTO_APPROVE))"
	@echo ""
	@echo "Examples:"
	@echo "  make init ENVIRONMENT=prod"
	@echo "  make plan"
	@echo "  make apply AUTO_APPROVE=true"
	@echo ""
	@echo "Using: $(TF_BINARY) at $(TERRAFORM_CMD)"

##@ OpenTofu/Terraform Operations

init: check-env check-secrets ## Initialize OpenTofu with backend config
	@echo -e "$(GREEN)Initializing $(TF_BINARY) for environment: $(ENVIRONMENT)$(NC)"
	@if [ ! -f $(BACKEND_CONFIG) ]; then \
		echo -e "$(RED)Backend config not found at $(BACKEND_CONFIG)$(NC)"; \
		echo "Creating backend resources..."; \
		./scripts/bootstrap-backend.sh $(ENVIRONMENT) $(REGION); \
	else \
		BUCKET=$$(grep '^bucket' $(BACKEND_CONFIG) | awk '{print $$3}' | tr -d '"'); \
		if ! aws s3api head-bucket --bucket $$BUCKET 2>/dev/null; then \
			echo -e "$(YELLOW)Backend S3 bucket does not exist. Creating backend resources...$(NC)"; \
			./scripts/bootstrap-backend.sh $(ENVIRONMENT) $(REGION); \
		fi; \
	fi
	@if [ ! -f $(TFVARS) ]; then \
		echo -e "$(RED)Terraform vars not found at $(TFVARS)$(NC)"; \
		echo "Please create $(TFVARS) from the example file"; \
		exit 1; \
	fi
	$(TERRAFORM_CMD) init -backend-config=$(BACKEND_CONFIG) -reconfigure

validate: init ## Validate OpenTofu configuration
	@echo -e "$(GREEN)Validating $(TF_BINARY) configuration...$(NC)"
	$(TERRAFORM_CMD) validate

fmt: ## Format OpenTofu files
	@echo -e "$(GREEN)Formatting $(TF_BINARY) files...$(NC)"
	$(TERRAFORM_CMD) fmt -recursive

fmt-check: ## Check if OpenTofu files are formatted
	@echo -e "$(GREEN)Checking $(TF_BINARY) formatting...$(NC)"
	$(TERRAFORM_CMD) fmt -check -recursive

plan: init ## Create execution plan
	@echo -e "$(GREEN)Creating $(TF_BINARY) plan for environment: $(ENVIRONMENT)$(NC)"
	$(TERRAFORM_CMD) plan -var-file=$(TFVARS) -out=tfplan

apply: plan ## Apply changes
	@echo -e "$(YELLOW)Applying changes to environment: $(ENVIRONMENT)$(NC)"
	@if [ "$(AUTO_APPROVE)" = "true" ]; then \
		$(TERRAFORM_CMD) apply tfplan; \
	else \
		$(TERRAFORM_CMD) apply tfplan; \
	fi
	@echo -e "$(GREEN)Deployment complete!$(NC)"
	@echo "Run 'make status' to check cluster status"

destroy: init ## Destroy all resources (WARNING: Destructive!)
	@echo -e "$(RED)WARNING: This will destroy all resources in environment: $(ENVIRONMENT)$(NC)"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read dummy
	@if [ "$(AUTO_APPROVE)" = "true" ]; then \
		$(TERRAFORM_CMD) destroy -var-file=$(TFVARS) -auto-approve; \
	else \
		$(TERRAFORM_CMD) destroy -var-file=$(TFVARS); \
	fi

refresh: init ## Refresh state
	@echo -e "$(GREEN)Refreshing $(TF_BINARY) state...$(NC)"
	$(TERRAFORM_CMD) refresh -var-file=$(TFVARS)

output: ## Show outputs
	@$(TERRAFORM_CMD) output -json | jq '.'

show: ## Show current state
	@$(TERRAFORM_CMD) show

##@ Kubernetes Operations

kubeconfig: ## Configure kubectl
	@echo -e "$(GREEN)Configuring kubectl...$(NC)"
	@CLUSTER=$$($(TERRAFORM_CMD) output -raw cluster_name 2>/dev/null) && \
	CLUSTER_REGION=$$($(TERRAFORM_CMD) output -raw region 2>/dev/null || echo $(REGION)) && \
	aws eks update-kubeconfig --region $$CLUSTER_REGION --name $$CLUSTER
	@echo "kubectl configured. Try: kubectl get nodes"

get-nodes: kubeconfig ## Get cluster nodes
	kubectl get nodes

get-pods: kubeconfig ## Get DaskHub pods
	kubectl get pods -n daskhub

logs-hub: kubeconfig ## Show hub logs
	kubectl logs -n daskhub deployment/hub -f

logs-proxy: kubeconfig ## Show proxy logs
	kubectl logs -n daskhub deployment/proxy -f

shell-hub: kubeconfig ## Open shell in hub pod
	kubectl exec -it -n daskhub deployment/hub -- /bin/bash

##@ Cost Management

kubecost-ui: kubeconfig ## Open Kubecost UI for cost monitoring
	@echo -e "$(GREEN)Opening Kubecost UI for environment: $(ENVIRONMENT)$(NC)"
	@./scripts/kubecost-ui.sh -e $(ENVIRONMENT)

cost-estimate: init ## Estimate costs (requires Infracost)
	@command -v infracost >/dev/null 2>&1 || { echo "Infracost not installed. See: https://www.infracost.io/docs/"; exit 1; }
	@echo -e "$(GREEN)Estimating costs for environment: $(ENVIRONMENT)$(NC)"
	infracost breakdown --path . --terraform-var-file $(TFVARS)

scale-down: kubeconfig ## Scale cluster to zero (save costs)
	@echo -e "$(YELLOW)Scaling down cluster to save costs...$(NC)"
	kubectl scale deployment --all -n daskhub --replicas=0
	@CLUSTER=$$($(TERRAFORM_CMD) output -raw cluster_name) && \
	CLUSTER_REGION=$$($(TERRAFORM_CMD) output -raw region 2>/dev/null || echo $(REGION)) && \
	aws eks update-nodegroup-config \
		--cluster-name $$CLUSTER \
		--nodegroup-name $$CLUSTER-main \
		--scaling-config minSize=0,desiredSize=0,maxSize=10 \
		--region $$CLUSTER_REGION
	@echo -e "$(GREEN)Cluster scaled down. Run 'make scale-up' to restore.$(NC)"

scale-up: kubeconfig ## Scale cluster back up
	@echo -e "$(GREEN)Scaling up cluster...$(NC)"
	@CLUSTER=$$($(TERRAFORM_CMD) output -raw cluster_name) && \
	CLUSTER_REGION=$$($(TERRAFORM_CMD) output -raw region 2>/dev/null || echo $(REGION)) && \
	aws eks update-nodegroup-config \
		--cluster-name $$CLUSTER \
		--nodegroup-name $$CLUSTER-main \
		--scaling-config minSize=1,desiredSize=1,maxSize=10 \
		--region $$CLUSTER_REGION
	kubectl scale deployment hub -n daskhub --replicas=1
	kubectl scale deployment proxy -n daskhub --replicas=1
	@echo -e "$(GREEN)Cluster scaled up. Services will be available in a few minutes.$(NC)"

##@ Maintenance

backup: ## Backup OpenTofu state
	@echo -e "$(GREEN)Backing up $(TF_BINARY) state...$(NC)"
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S) && \
	$(TERRAFORM_CMD) state pull > backups/terraform-state-$$TIMESTAMP.json
	@echo "State backed up to backups/"

clean: ## Clean up temporary files
	@echo -e "$(YELLOW)Cleaning up temporary files...$(NC)"
	rm -rf .terraform .terraform.lock.hcl tfplan *.tfstate *.tfstate.*
	@echo -e "$(GREEN)Cleanup complete$(NC)"

status: kubeconfig ## Check cluster and application status
	@echo -e "$(GREEN)=== Cluster Status ===$(NC)"
	@CLUSTER=$$($(TERRAFORM_CMD) output -raw cluster_name 2>/dev/null) && \
	CLUSTER_REGION=$$($(TERRAFORM_CMD) output -raw region 2>/dev/null || echo $(REGION)) && \
	aws eks describe-cluster --name $$CLUSTER --region $$CLUSTER_REGION --query 'cluster.status' --output text
	@echo ""
	@echo -e "$(GREEN)=== Node Status ===$(NC)"
	kubectl get nodes 2>/dev/null || echo "kubectl not configured"
	@echo ""
	@echo -e "$(GREEN)=== DaskHub/Dask Gateway Status ===$(NC)"
	kubectl get pods -n daskhub 2>/dev/null || echo "DaskHub namespace not found"
	@echo ""
	@# Check if this is a standalone Gateway deployment
	@if $(TERRAFORM_CMD) output -raw dask_gateway_api_token 2>/dev/null | grep -qv "N/A"; then \
		echo -e "$(GREEN)╔════════════════════════════════════════════════════════════════════════╗$(NC)"; \
		echo -e "$(GREEN)║          🌐 DASK GATEWAY CONNECTION INFO (Standalone Mode)            ║$(NC)"; \
		echo -e "$(GREEN)╚════════════════════════════════════════════════════════════════════════╝$(NC)"; \
		echo ""; \
		echo -e "$(YELLOW)📍 Gateway URL:$(NC)"; \
		GW_LB=$$(kubectl get svc -n daskhub dask-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "LoadBalancer not ready yet"); \
		echo "  $$GW_LB:8000"; \
		echo ""; \
		echo -e "$(YELLOW)🔑 API Token:$(NC)"; \
		echo "  Run: make output | jq -r '.dask_gateway_api_token.value'"; \
		echo "  Or: $(TERRAFORM_CMD) output -raw dask_gateway_api_token"; \
		echo ""; \
		echo -e "$(YELLOW)🐍 Python Connection (for CryoCloud):$(NC)"; \
		echo "  from dask_gateway import Gateway, BasicAuth"; \
		echo "  gateway = Gateway('http://$$GW_LB:8000', auth=BasicAuth('dask', '<TOKEN>'))"; \
		echo "  cluster = gateway.new_cluster()"; \
		echo "  cluster.scale(10)"; \
		echo ""; \
		echo -e "$(YELLOW)📊 Full Connection Info:$(NC)"; \
		echo "  $(TERRAFORM_CMD) output dask_gateway_connection_info"; \
		echo ""; \
	else \
		echo -e "$(GREEN)🚀 Access Your JupyterHub ===$(NC)"; \
		echo ""; \
		echo -e "$(YELLOW)Get Load Balancer URL:$(NC)"; \
		echo "  kubectl get svc -n daskhub proxy-public"; \
		echo ""; \
		LB=$$(kubectl get svc -n daskhub proxy-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Load balancer not ready"); \
		echo -e "$(YELLOW)Your URL:$(NC)"; \
		echo "  http://$$LB"; \
		echo ""; \
		echo -e "$(YELLOW)Login (Dummy Auth - Test):$(NC)"; \
		echo "  Username: any value (e.g., testuser)"; \
		echo "  Password: any value"; \
		echo ""; \
	fi

test-login: ## Test JupyterHub login
	@URL=$$($(TERRAFORM_CMD) output -raw jupyterhub_url 2>/dev/null) && \
	echo -e "$(GREEN)Testing JupyterHub at $$URL$(NC)" && \
	curl -s -o /dev/null -w "%{http_code}" $$URL || echo "Connection failed"

##@ Development

lint: fmt-check validate ## Run all linters
	@echo -e "$(GREEN)Running linters...$(NC)"
	@command -v tflint >/dev/null 2>&1 || { echo "tflint not installed. See: https://github.com/terraform-linters/tflint"; exit 1; }
	tflint --init
	tflint

docs: ## Generate documentation
	@echo -e "$(GREEN)Generating documentation...$(NC)"
	@command -v terraform-docs >/dev/null 2>&1 || { echo "terraform-docs not installed. See: https://terraform-docs.io/"; exit 1; }
	terraform-docs markdown . > TERRAFORM_DOCS.md

graph: ## Generate resource graph
	@echo -e "$(GREEN)Generating resource graph...$(NC)"
	$(TERRAFORM_CMD) graph | dot -Tpng > infrastructure-graph.png
	@echo "Graph saved to infrastructure-graph.png"

##@ Import Operations

#import-existing: ## Import existing Pangeo cluster
#	@echo -e "$(GREEN)Starting import of existing cluster...$(NC)"
#	./scripts/import-existing-pangeo.sh

post-import-validate: ## Validate imported configuration
	@echo -e "$(GREEN)Validating imported configuration...$(NC)"
	$(TERRAFORM_CMD) init -backend-config=backend.tfvars
	$(TERRAFORM_CMD) plan
	@echo -e "$(GREEN)If plan shows no changes, import was successful!$(NC)"

##@ Utilities

check-env: ## Check environment setup
	@echo -e "$(GREEN)Checking environment setup...$(NC)"
	@echo "OpenTofu/Terraform: $(TF_BINARY) at $(TERRAFORM_CMD)"
	@echo "AWS CLI: $$(which aws)"
	@echo "kubectl: $$(which kubectl || echo 'not found')"
	@echo "Environment: $(ENVIRONMENT)"
	@echo "Region: $(REGION)"
	@aws sts get-caller-identity >/dev/null 2>&1 || { echo -e "$(RED)AWS credentials not configured$(NC)"; exit 1; }
	@echo -e "$(GREEN)Environment check passed$(NC)"

check-secrets: ## Check if secrets.yaml exists and is encrypted
	@SECRETS_FILE="environments/$(ENVIRONMENT)/secrets.yaml"; \
	SECRETS_EXAMPLE="environments/dev/secrets.yaml.example"; \
	if [ ! -f "$$SECRETS_FILE" ]; then \
		echo -e "$(YELLOW)secrets.yaml not found at $$SECRETS_FILE$(NC)"; \
		echo -e "$(GREEN)Creating and encrypting secrets file...$(NC)"; \
		if ! command -v sops >/dev/null 2>&1; then \
			echo -e "$(RED)Error: SOPS not found. Install it first:$(NC)"; \
			echo "  brew install sops"; \
			echo "  # or"; \
			echo "  https://github.com/getsops/sops/releases"; \
			exit 1; \
		fi; \
		if [ -f "$$SECRETS_EXAMPLE" ]; then \
			cp "$$SECRETS_EXAMPLE" "$$SECRETS_FILE"; \
			echo "Created $$SECRETS_FILE from example file"; \
		else \
			printf 'cognito:\n  client_secret: test-secret-change-me\ngithub:\n  token: ""\ndatabase:\n  password: ""\nsmtp:\n  username: ""\n  password: ""\ndatadog:\n  api_key: ""\nslack:\n  webhook_url: ""\n' > "$$SECRETS_FILE"; \
			echo "Created $$SECRETS_FILE with default template"; \
		fi; \
		echo "Encrypting with SOPS..."; \
		if sops -e -i "$$SECRETS_FILE"; then \
			echo -e "$(GREEN)✓ Created and encrypted $$SECRETS_FILE$(NC)"; \
			echo ""; \
			echo -e "$(YELLOW)Note: Default secrets were used. Update them if needed:$(NC)"; \
			echo "  sops $$SECRETS_FILE"; \
		else \
			echo -e "$(RED)Failed to encrypt $$SECRETS_FILE$(NC)"; \
			echo "Check that .sops.yaml is configured correctly for $(ENVIRONMENT) environment"; \
			rm -f "$$SECRETS_FILE"; \
			exit 1; \
		fi; \
	elif ! grep -q "^sops:" "$$SECRETS_FILE" 2>/dev/null; then \
		echo -e "$(YELLOW)Warning: $$SECRETS_FILE exists but may not be SOPS-encrypted$(NC)"; \
		echo "Encrypting with SOPS..."; \
		if sops -e -i "$$SECRETS_FILE"; then \
			echo -e "$(GREEN)✓ Encrypted $$SECRETS_FILE$(NC)"; \
		else \
			echo -e "$(RED)Failed to encrypt $$SECRETS_FILE$(NC)"; \
			exit 1; \
		fi; \
	fi

install-tools: ## Install required tools
	@echo -e "$(GREEN)Installing required tools...$(NC)"
	@echo "Installing OpenTofu..."
	@curl -fsSL https://get.opentofu.org/install-opentofu.sh | bash -s -- --install-method standalone
	@echo "Installing kubectl..."
	@curl -LO "https://dl.k8s.io/release/$$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
	@chmod +x kubectl && sudo mv kubectl /usr/local/bin/
	@echo "Installing Helm..."
	@curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
	@echo -e "$(GREEN)Tools installed$(NC)"

# Hidden targets for advanced users
.PHONY: force-unlock console debug

force-unlock: ## Force unlock state (use with caution)
	@echo -e "$(RED)Force unlocking state...$(NC)"
	$(TERRAFORM_CMD) force-unlock $(LOCK_ID)

console: init ## Open OpenTofu console
	$(TERRAFORM_CMD) console

debug: ## Enable debug output
	TF_LOG=DEBUG $(TERRAFORM_CMD) plan -var-file=$(TFVARS)

##@ Docker Image Management

IMAGE_NAME ?= dasktest-notebook
IMAGE_TAG ?= latest
BASE_TAG ?= 2025.01.10
DOCKER_REGISTRY ?=
DOCKER_PUSH ?= false

build-image: ## Build custom Docker image
	@echo -e "$(GREEN)Building Docker image...$(NC)"
	@if [ ! -f docker/Dockerfile ]; then \
		echo -e "$(RED)Error: docker/Dockerfile not found$(NC)"; \
		exit 1; \
	fi
	@cd docker && \
		export DOCKER_REGISTRY=$(DOCKER_REGISTRY) && \
		export DOCKER_PUSH=$(DOCKER_PUSH) && \
		./build.sh $(IMAGE_TAG) $(BASE_TAG)
	@echo -e "$(GREEN)Image build complete!$(NC)"

test-image: ## Test the custom Docker image
	@echo -e "$(GREEN)Testing Docker image...$(NC)"
	@FULL_IMAGE=$$(if [ -n "$(DOCKER_REGISTRY)" ]; then echo "$(DOCKER_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)"; else echo "$(IMAGE_NAME):$(IMAGE_TAG)"; fi); \
	echo "Testing image: $$FULL_IMAGE"; \
	docker run --rm $$FULL_IMAGE python -c "import vaex; import mortie; print('✅ All imports successful')"
	@echo -e "$(GREEN)Image test passed!$(NC)"

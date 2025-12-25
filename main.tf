# Tofu JupyterHub - Main OpenTofu Configuration
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "registry.opentofu.org/hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "registry.opentofu.org/hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "registry.opentofu.org/hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "registry.opentofu.org/hashicorp/random"
      version = "~> 3.6"
    }
    sops = {
      source  = "registry.opentofu.org/carlpett/sops"
      version = "~> 1.0"
    }
  }

  # Backend configuration is defined in backend.tf and configured via backend.tfvars
  # OpenTofu supports native state encryption configured in encryption.tf
}

# Import native encryption configuration for OpenTofu
# This provides state, plan, and output encryption using AWS KMS
# See encryption.tf for detailed configuration

# Provider Configuration
provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.region]
    }
  }
}

provider "sops" {}

# Load encrypted secrets
data "sops_file" "secrets" {
  source_file = "${path.module}/environments/${var.environment}/secrets.yaml"
}

# Local variables
locals {
  common_tags = {
    Environment = var.environment
    Application = "jupyterhub"
    Terraform   = "true"
    Owner       = var.owner_email
    CostCenter  = var.cost_center
  }

  cluster_name = "${var.cluster_name}-${var.environment}"

  # Extract secrets
  cognito_client_secret = data.sops_file.secrets.data["cognito.client_secret"]
  github_token          = try(data.sops_file.secrets.data["github.token"], "")
  github_client_id      = try(data.sops_file.secrets.data["github.client_id"], "")
  github_client_secret  = try(data.sops_file.secrets.data["github.client_secret"], "")

  # Cost optimization flags
  enable_nat_gateway = var.enable_nat_gateway

  # Node group configuration
  main_node_config = {
    min_size     = var.scale_to_zero ? 0 : var.main_node_min_size
    desired_size = var.scale_to_zero ? 0 : var.main_node_desired_size
    max_size     = var.main_node_max_size
  }

  dask_node_config = {
    min_size     = var.scale_to_zero ? 0 : var.dask_node_min_size
    desired_size = var.scale_to_zero ? 0 : var.dask_node_desired_size
    max_size     = var.dask_node_max_size
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Module: Networking
module "networking" {
  source = "./modules/networking"

  cluster_name       = local.cluster_name
  region             = var.region
  availability_zones = data.aws_availability_zones.available.names
  vpc_cidr           = var.vpc_cidr
  enable_nat_gateway = local.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway
  tags               = local.common_tags
}

# Module: KMS
module "kms" {
  source = "./modules/kms"

  cluster_name = local.cluster_name
  environment  = var.environment
  tags         = local.common_tags
}

# Module: Cognito (only for JupyterHub deployments)
module "cognito" {
  count  = var.enable_jupyterhub ? 1 : 0
  source = "./modules/cognito"

  cluster_name = local.cluster_name
  domain_name  = var.domain_name
  environment  = var.environment
  admin_email  = var.admin_email
  tags         = local.common_tags
}

# Module: S3
module "s3" {
  source = "./modules/s3"

  cluster_name       = local.cluster_name
  environment        = var.environment
  region             = var.region
  force_destroy      = var.force_destroy_s3
  lifecycle_days     = var.s3_lifecycle_days
  enable_cur         = var.enable_kubecost
  cur_retention_days = 90
  tags               = local.common_tags
}

# Module: ACM Certificate
module "acm" {
  count  = var.enable_acm ? 1 : 0
  source = "./modules/acm"

  domain_name        = var.domain_name
  enable_wildcard    = var.acm_enable_wildcard
  auto_validate      = var.acm_auto_validate
  validation_timeout = var.acm_validation_timeout
  tags               = local.common_tags
}

# Module: EKS
module "eks" {
  source = "./modules/eks"

  cluster_name         = local.cluster_name
  cluster_version      = var.kubernetes_version
  region               = var.region
  vpc_id               = module.networking.vpc_id
  subnet_ids           = module.networking.private_subnet_ids
  main_node_subnet_ids = var.pin_main_nodes_single_az ? module.networking.first_private_subnet_id : null
  kms_key_id           = module.kms.key_id

  # 3-Node-Group Architecture
  use_three_node_groups = var.use_three_node_groups

  # System node group (3-node architecture)
  system_node_instance_types   = var.system_node_instance_types
  system_node_min_size         = var.system_node_min_size
  system_node_desired_size     = var.system_node_desired_size
  system_node_max_size         = var.system_node_max_size
  system_enable_spot_instances = var.system_enable_spot_instances

  # User node group (3-node architecture)
  user_node_instance_types   = var.user_node_instance_types
  user_node_subnet_ids       = var.pin_user_nodes_single_az ? module.networking.first_private_subnet_id : null
  user_node_min_size         = var.user_node_min_size
  user_node_desired_size     = var.user_node_desired_size
  user_node_max_size         = var.user_node_max_size
  user_enable_spot_instances = var.user_enable_spot_instances

  # Main node group (legacy 2-node architecture)
  main_node_instance_types   = var.main_node_instance_types
  main_node_min_size         = local.main_node_config.min_size
  main_node_desired_size     = local.main_node_config.desired_size
  main_node_max_size         = local.main_node_config.max_size
  main_enable_spot_instances = var.main_enable_spot_instances

  # Dask worker node group (both architectures)
  dask_node_instance_types   = var.dask_node_instance_types
  dask_node_min_size         = local.dask_node_config.min_size
  dask_node_desired_size     = local.dask_node_config.desired_size
  dask_node_max_size         = local.dask_node_config.max_size
  dask_enable_spot_instances = var.dask_enable_spot_instances

  tags = local.common_tags

  depends_on = [module.networking]
}

# Module: Kubernetes Resources
module "kubernetes" {
  source = "./modules/kubernetes"

  cluster_name      = local.cluster_name
  s3_bucket         = module.s3.bucket_name
  kms_key_id        = module.kms.key_id
  oidc_provider_arn = module.eks.oidc_provider_arn

  depends_on = [module.eks]
}

# Module: Helm Releases
module "helm" {
  source = "./modules/helm"

  cluster_name          = local.cluster_name
  domain_name           = var.domain_name
  certificate_arn       = var.enable_acm ? module.acm[0].certificate_arn : ""
  s3_bucket             = module.s3.bucket_name
  cognito_client_id     = var.enable_jupyterhub ? module.cognito[0].client_id : ""
  cognito_client_secret = var.enable_jupyterhub ? local.cognito_client_secret : ""
  cognito_domain        = var.enable_jupyterhub ? module.cognito[0].domain : ""
  cognito_user_pool_id  = var.enable_jupyterhub ? module.cognito[0].user_pool_id : ""
  admin_email           = var.admin_email

  # Deployment type
  enable_jupyterhub = var.enable_jupyterhub

  # Container image configuration
  singleuser_image_name = var.singleuser_image_name
  singleuser_image_tag  = var.singleuser_image_tag

  # Resource limits
  user_cpu_guarantee    = var.user_cpu_guarantee
  user_cpu_limit        = var.user_cpu_limit
  user_memory_guarantee = var.user_memory_guarantee
  user_memory_limit     = var.user_memory_limit

  # Dask configuration
  dask_worker_cores_max  = var.dask_worker_cores_max
  dask_worker_memory_max = var.dask_worker_memory_max
  dask_cluster_max_cores = var.dask_cluster_max_cores

  # Idle timeouts
  kernel_cull_timeout = var.kernel_cull_timeout
  server_cull_timeout = var.server_cull_timeout

  # Cluster autoscaler
  region                      = var.region
  cluster_autoscaler_role_arn = module.eks.cluster_autoscaler_arn

  # Node group architecture
  use_three_node_groups = var.use_three_node_groups

  # JupyterLab profile selection
  enable_profile_selection = var.enable_profile_selection

  # GitHub OAuth authentication
  github_enabled        = var.github_enabled
  github_client_id      = local.github_client_id
  github_client_secret  = local.github_client_secret
  github_org_whitelist  = var.github_org_whitelist

  depends_on = [module.kubernetes]
}

# Module: Kubecost (Cost Monitoring)
module "kubecost_irsa" {
  count  = var.enable_kubecost ? 1 : 0
  source = "./modules/irsa"

  cluster_name      = local.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  namespace         = "kubecost"
  service_account   = "kubecost-cost-analyzer"

  policy_statements = [
    {
      Effect = "Allow"
      Action = [
        "ce:GetCostAndUsage",
        "ce:GetCostForecast",
        "s3:GetObject",
        "s3:ListBucket",
        "athena:StartQueryExecution",
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "glue:GetDatabase",
        "glue:GetTable",
        "glue:GetPartitions"
      ]
      Resource = "*"
    }
  ]

  tags = local.common_tags
}

module "kubecost" {
  count  = var.enable_kubecost ? 1 : 0
  source = "./modules/kubecost"

  cluster_name           = local.cluster_name
  region                 = var.region
  cur_bucket_name        = module.s3.cur_bucket_name
  kubecost_irsa_role_arn = module.kubecost_irsa[0].role_arn

  # Public access configuration
  expose_via_loadbalancer       = var.kubecost_expose_public
  kubecost_basic_auth_enabled   = var.kubecost_enable_auth
  kubecost_basic_auth_password  = var.kubecost_auth_password

  # Node selector based on architecture
  node_selector = var.use_three_node_groups ? {
    role = "system"
  } : {
    role = "main"
  }

  # No tolerations needed - system nodes don't have taints
  tolerations = []

  tags       = local.common_tags
  depends_on = [module.helm, module.kubecost_irsa]
}

# Module: Monitoring (Optional)
module "monitoring" {
  count  = var.enable_monitoring ? 1 : 0
  source = "./modules/monitoring"

  cluster_name = local.cluster_name
  region       = var.region
  tags         = local.common_tags

  depends_on = [module.eks]
}

# Module: Auto-shutdown (Optional)
module "auto_shutdown" {
  count  = var.enable_auto_shutdown ? 1 : 0
  source = "./modules/auto_shutdown"

  cluster_name      = local.cluster_name
  environment       = var.environment
  shutdown_schedule = var.shutdown_schedule
  startup_schedule  = var.startup_schedule
  tags              = local.common_tags

  depends_on = [module.eks]
}
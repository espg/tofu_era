# Terra JupyterHub - Output Values

# Cluster Information
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_endpoint" {
  description = "Endpoint for EKS cluster"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster's OIDC issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

# Network Information
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.networking.public_subnet_ids
}

# KMS Information
output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = module.kms.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = module.kms.key_arn
}

# S3 Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for JupyterHub data"
  value       = module.s3.bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for JupyterHub data"
  value       = module.s3.bucket_arn
}

# Cognito Information (only for JupyterHub deployments)
output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = var.enable_jupyterhub ? module.cognito[0].user_pool_id : "N/A - Standalone Gateway"
}

output "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = var.enable_jupyterhub ? module.cognito[0].user_pool_arn : "N/A - Standalone Gateway"
}

output "cognito_client_id" {
  description = "ID of the Cognito App Client"
  value       = var.enable_jupyterhub ? module.cognito[0].client_id : "N/A - Standalone Gateway"
  sensitive   = true
}

output "cognito_domain" {
  description = "Cognito domain for authentication"
  value       = var.enable_jupyterhub ? module.cognito[0].domain : "N/A - Standalone Gateway"
}

# ACM Certificate
output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = var.enable_acm ? module.acm[0].certificate_arn : "N/A - ACM disabled"
}

output "certificate_status" {
  description = "Status of the ACM certificate"
  value       = var.enable_acm ? module.acm[0].certificate_status : "N/A - ACM disabled"
}

output "acm_certificate_validation_records" {
  description = "DNS validation records for ACM certificate (add these to your DNS provider)"
  value       = var.enable_acm ? module.acm[0].dns_validation_records : []
}

output "acm_validation_instructions" {
  description = "Instructions for validating the ACM certificate"
  value       = var.enable_acm ? module.acm[0].validation_instructions : null
}

# JupyterHub Access Information (only for JupyterHub deployments)
output "jupyterhub_url" {
  description = "URL to access JupyterHub"
  value       = !var.enable_jupyterhub ? "N/A - Standalone Gateway" : (var.enable_acm ? "https://${var.domain_name}" : "http://${var.domain_name} (or use load balancer URL)")
}

output "login_instructions" {
  description = "Instructions for logging into JupyterHub or connecting to Dask Gateway"
  value = !var.enable_jupyterhub ? "See dask_gateway_connection_info output for Gateway connection details" : (var.enable_acm ? join("\n", [
    "To access JupyterHub:",
    "1. Navigate to: https://${var.domain_name}",
    "2. Log in with your Cognito credentials",
    "3. First-time users need to be added to Cognito User Pool",
    "",
    "To add a new user:",
    "aws cognito-idp admin-create-user \\",
    "  --user-pool-id ${var.enable_jupyterhub ? module.cognito[0].user_pool_id : ""} \\",
    "  --username <email> \\",
    "  --user-attributes Name=email,Value=<email> Name=email_verified,Value=true \\",
    "  --temporary-password <temp-password> \\",
    "  --message-action SUPPRESS \\",
    "  --region ${var.region}"
    ]) : join("\n", [
    "To access JupyterHub (HTTP mode):",
    "1. Get load balancer URL: kubectl get svc -n daskhub proxy-public",
    "2. Navigate to: http://<load-balancer-url>",
    "3. Login with any username/password (dummy auth for testing)"
  ]))
}

# Dask Gateway Connection Information (for standalone Gateway deployments)
output "dask_gateway_api_token" {
  description = "API token for Dask Gateway authentication"
  value       = var.enable_jupyterhub ? "N/A - Use JupyterHub" : module.helm.gateway_token
  sensitive   = true
}

output "dask_gateway_connection_info" {
  description = "Connection information and example code for Dask Gateway"
  value       = var.enable_jupyterhub ? "N/A - Use JupyterHub for Dask Gateway access" : <<-EOT
╔════════════════════════════════════════════════════════════════════════╗
║                    DASK GATEWAY CONNECTION INFO                        ║
╚════════════════════════════════════════════════════════════════════════╝

📍 GATEWAY URL:
   Run this command to get the LoadBalancer URL:

   kubectl get svc -n daskhub dask-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

🔑 API TOKEN (Sensitive - Store Securely):
   Run this command to retrieve:

   tofu output -raw dask_gateway_api_token

🐍 PYTHON CONNECTION CODE:
   Use this code from CryoCloud JupyterHub:

   ```python
   from dask_gateway import Gateway, BasicAuth

   # Replace <GATEWAY_URL> with the LoadBalancer hostname
   gateway_url = "http://<GATEWAY_URL>:8000"

   # Get token from: tofu output -raw dask_gateway_api_token
   gateway_token = "<YOUR_TOKEN_HERE>"

   # Connect to Gateway
   gateway = Gateway(
       gateway_url,
       auth=BasicAuth("dask", gateway_token)
   )

   # List available clusters
   gateway.list_clusters()

   # Create a new cluster
   cluster = gateway.new_cluster()
   cluster.scale(10)  # Request 10 workers

   # Connect Dask client
   from dask.distributed import Client
   client = Client(cluster)

   # Submit work
   def square(x):
       return x ** 2

   futures = client.map(square, range(100))
   results = client.gather(futures)
   ```

📊 CLUSTER CONFIGURATION:
   • Max cores per cluster: ${var.dask_cluster_max_cores}
   • Worker cores: ${var.dask_worker_cores_max}
   • Worker memory: ${var.dask_worker_memory_max}GB
   • Max nodes: ${local.main_node_config.max_size}
   • Idle timeout: ${var.server_cull_timeout}s (${var.server_cull_timeout / 60} minutes)

💰 COST NOTES:
   • Minimum 1 node always running for Gateway scheduler (~$15-20/month spot)
   • Additional worker nodes scale down when clusters terminated
   • S3 data transfer via VPC endpoint (no NAT charges) ✅
   • Spot instances for all nodes (60-90% cost savings)

⚠️  SECURITY:
   • Keep API token secure
   • Gateway exposed via public LoadBalancer (token auth only)
   • Consider IP allowlisting for production use

EOT
}

# kubectl Configuration
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly costs breakdown"
  value = {
    eks_cluster   = "$72.00 (Control plane)"
    main_nodes    = "${format("%.2f", local.main_node_config.desired_size * 140.16)} (r5.xlarge on-demand)"
    dask_nodes    = "$0.00 when scaled to zero, ~${format("%.2f", var.dask_node_max_size * 0.096 * 24 * 30)} max with spot"
    nat_gateway   = local.enable_nat_gateway ? "$45.00 per gateway" : "$0.00 (disabled)"
    load_balancer = "~$20.00"
    s3_storage    = "Variable based on usage"
    cognito       = "Free tier covers most usage"
    total_minimum = "${format("%.2f", 72.00 + (local.main_node_config.desired_size * 140.16) + (local.enable_nat_gateway ? 45.00 : 0.00) + 20.00)}"
  }
}

# Debug Information
output "debug_info" {
  description = "Debug information for troubleshooting"
  value = {
    environment              = var.environment
    region                   = var.region
    account_id               = data.aws_caller_identity.current.account_id
    nat_gateway_enabled      = local.enable_nat_gateway
    main_spot_instances      = var.main_enable_spot_instances
    dask_spot_instances      = var.dask_enable_spot_instances
    scale_to_zero            = var.scale_to_zero
    auto_shutdown            = var.enable_auto_shutdown
  }
  sensitive = true
}

# Module-specific Outputs
output "networking_outputs" {
  description = "All outputs from networking module"
  value       = module.networking
  sensitive   = true
}

output "eks_outputs" {
  description = "All outputs from EKS module"
  value       = module.eks
  sensitive   = true
}

output "helm_outputs" {
  description = "All outputs from Helm module"
  value       = module.helm
  sensitive   = true
}

# State Management
output "terraform_state_bucket" {
  description = "S3 bucket used for Terraform state"
  value       = "Check backend.tfvars for state bucket configuration"
}

# Quick Start Commands
output "quick_start" {
  description = "Quick start commands for cluster access"
  value       = <<EOT
# Configure kubectl
aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}

# Test connection
kubectl get nodes

# Get JupyterHub pods
kubectl get pods -n jupyterhub

# Get JupyterHub service
kubectl get svc -n jupyterhub

# Follow JupyterHub logs
kubectl logs -n jupyterhub deployment/hub -f

# Get Load Balancer URL
kubectl get svc -n jupyterhub proxy-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
EOT
}

# Monitoring URLs (if enabled)
output "monitoring_urls" {
  description = "URLs for monitoring dashboards"
  value = var.enable_monitoring ? {
    cloudwatch_dashboard = "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${local.cluster_name}"
    container_insights   = "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#container-insights:performance/EKS:cluster?~(query~'${local.cluster_name})"
  } : null
}

# Maintenance Commands
output "maintenance_commands" {
  description = "Useful maintenance commands"
  value       = <<EOT
# Scale nodes to zero (cost savings)
kubectl scale deployment hub -n jupyterhub --replicas=0
aws eks update-nodegroup-config --cluster-name ${module.eks.cluster_name} --nodegroup-name main --scaling-config minSize=0,maxSize=0,desiredSize=0

# Restart JupyterHub
kubectl rollout restart deployment/hub -n jupyterhub

# Clean up user pods
kubectl delete pods -n jupyterhub -l component=singleuser-server

# Update JupyterHub configuration
helm upgrade jupyterhub jupyterhub/jupyterhub -n jupyterhub --values helm-values.yaml
EOT
}
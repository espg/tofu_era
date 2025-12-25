# Terraform Backend Configuration - Development
# This configures where Terraform state is stored

bucket         = "terraform-state-jupyterhub-dev"  # Change to your S3 bucket
key            = "jupyterhub/terraform.tfstate"
region         = "us-west-2"
encrypt        = true
dynamodb_table = "terraform-state-lock-dev"  # For state locking

# Note: These resources should be created manually or with a bootstrap script
# See scripts/bootstrap-backend.sh
# Terraform Backend Configuration - Englacial Environment
# Will be created automatically by: make init ENVIRONMENT=englacial

bucket         = "tofu-state-jupyterhub-englacial-usw2-429435741471"
key            = "terraform.tfstate"
region         = "us-west-2"
encrypt        = true
dynamodb_table = "tofu-state-lock-englacial-usw2"

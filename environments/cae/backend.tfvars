# Terraform Backend Configuration - CAE Production Environment
# Will be created automatically by: make init ENVIRONMENT=cae
# Account: 390197508439

bucket         = "tofu-state-jupyterhub-cae-usw2-390197508439"
key            = "terraform.tfstate"
region         = "us-west-2"
encrypt        = true
dynamodb_table = "tofu-state-lock-cae-usw2"

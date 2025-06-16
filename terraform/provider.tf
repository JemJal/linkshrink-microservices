# provider.tf

# Specifies the required provider (AWS) and its version.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configures the AWS provider, setting the region.
provider "aws" {
  region = var.aws_region
}
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
  region = "eu-north-1" # Or your chosen region
}
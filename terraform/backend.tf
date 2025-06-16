# Backend.tf

terraform {
  backend "s3" {
    # Use the unique bucket name you just created
    bucket         = "linkshrink-terraform-state-cem-12345"
    # This is the path/filename for the state file inside the bucket
    key            = "global/terraform.tfstate"
    region         = "eu-north-1"

    # Use the lock table name you just created
    dynamodb_table = "linkshrink-terraform-lock"
  }
}
# terraform/ecr.tf

# ECR Repository for the user-service
resource "aws_ecr_repository" "user_service" {
  name = "user-service"
  force_delete = true
}

resource "aws_ecr_repository" "link_service" {
  name         = "link-service"
  force_delete = true
}

resource "aws_ecr_repository" "redirect_service" {
  name         = "redirect-service"
  force_delete = true
}

# NOTE: force_delete is useful for development but should be
#   removed or set to false in a production environment to
#   prevent accidental deletion of important images.
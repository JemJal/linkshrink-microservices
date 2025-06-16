# terraform/ecr.tf

# ECR Repository for the user-service
resource "aws_ecr_repository" "user_service" {
  name = "user-service"

  # NOTE: force_delete is useful for development but should be
  # removed or set to false in a production environment to
  # prevent accidental deletion of important images.
  force_delete = true
}
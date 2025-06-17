# terraform/ecr.tf

# ECR Repositories for all our application services, configured with production best practices.

resource "aws_ecr_repository" "user_service" {
  name                 = "user-service"
  image_tag_mutability = "IMMUTABLE" # Prevents overwriting tags
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true # Scans for vulnerabilities
  }
}

resource "aws_ecr_repository" "link_service" {
  name                 = "link-service"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "redirect_service" {
  name                 = "redirect-service"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "analytics_service" {
  name                 = "analytics-service"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "web_gui_service" {
  name                 = "web-gui-service"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
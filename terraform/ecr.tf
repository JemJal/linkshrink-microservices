# terraform/ecr.tf
resource "aws_ecr_repository" "user_service" {
  name = "user-service"
  image_tag_mutability = "IMMUTABLE"
  force_delete = true
  image_scanning_configuration { scan_on_push = true }
}
resource "aws_ecr_repository" "link_service" {
  name = "link-service"
  image_tag_mutability = "IMMUTABLE"
  force_delete = true
  image_scanning_configuration { scan_on_push = true }
}
resource "aws_ecr_repository" "redirect_service" {
  name = "redirect-service"
  image_tag_mutability = "IMMUTABLE"
  force_delete = true
  image_scanning_configuration { scan_on_push = true }
}
resource "aws_ecr_repository" "analytics_service" {
  name = "analytics-service"
  image_tag_mutability = "IMMUTABLE"
  force_delete = true
  image_scanning_configuration { scan_on_push = true }
}
# UPDATED: Replaced web-gui-service with the new Vue app repository
resource "aws_ecr_repository" "linkshrink_vue_gui" {
  name = "linkshrink-vue-gui"
  image_tag_mutability = "IMMUTABLE"
  force_delete = true
  image_scanning_configuration { scan_on_push = true }
}
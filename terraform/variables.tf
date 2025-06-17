# variables.tf
variable "db_password" {
  description = "The password for the RDS database"
  type        = string
  sensitive   = true # This hides the value in Terraform's output
}

variable "image_tag" {
  description = "The tag of the Docker image to deploy"
  type        = string
  default     = "latest" # We'll override this in our CI/CD pipeline
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "eu-north-1"
}

variable "link_db_password" {
  description = "The password for the link-service RDS database."
  type        = string
  sensitive   = true
}

variable "jwt_secret_key" {
  description = "The password for the link-service RDS database."
  type        = string
  sensitive   = true
}

variable "mq_password" {
  description = "The password for the RabbitMQ admin user."
  type        = string
  sensitive   = true
}
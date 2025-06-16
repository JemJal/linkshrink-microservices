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
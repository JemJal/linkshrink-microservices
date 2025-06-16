# terraform/vpc_endpoints.tf

# Endpoint for ECR API
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.ecs_service_sg.id]
  subnet_ids          = aws_subnet.private[*].id
  tags = {
    Name = "linkshrink-ecr-api-endpoint"
  }
}

# Endpoint for ECR Docker Registry
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.ecs_service_sg.id]
  subnet_ids          = aws_subnet.private[*].id
  tags = {
    Name = "linkshrink-ecr-dkr-endpoint"
  }
}

# Gateway Endpoint for S3 (needed by ECR to download image layers)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # ================= CRITICAL FIX 2 =================
  # You need to associate the S3 Gateway with ALL route tables
  # that need to access it. The private subnets were missing.
  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private.id
  ]
  # ==================================================

  tags = {
    Name = "linkshrink-s3-gateway-endpoint"
  }
}
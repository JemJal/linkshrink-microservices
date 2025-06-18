# terraform/security.tf

# 1. Security Group for our ALB
resource "aws_security_group" "alb_sg" {
  name        = "linkshrink-alb-sg"
  description = "Allows web traffic to the ALB"
  vpc_id      = aws_vpc.main.id
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # This new rule allows secure HTTPS traffic to reach your new listener.
  ingress {
    description = "Allow HTTPS traffic from anywhere"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. Security Group for our ECS Fargate Service
resource "aws_security_group" "ecs_service_sg" {
  name        = "linkshrink-ecs-service-sg"
  description = "Allows traffic from ALB to the ECS tasks"
  vpc_id      = aws_vpc.main.id

  # This is your EXISTING rule for all the Python backend services
  ingress {
    description     = "Allow traffic from ALB on port 8000 for backend services"
    protocol        = "tcp"
    from_port       = 8000
    to_port         = 8000
    security_groups = [aws_security_group.alb_sg.id]
  }

  # --- THIS IS THE NEW RULE YOU ARE ADDING ---
  # It allows the ALB health check and user traffic to reach the Nginx frontend container on port 80.
  ingress {
    description     = "Allow traffic from ALB on port 80 for frontend service"
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.alb_sg.id]
  }
  # -------------------------------------------

  # This is your EXISTING rule for VPC Endpoints
  ingress {
    description = "Allow members to talk to each other (for VPC Endpoints)"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    self        = true
  }
  
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. Security Group for our RDS Database
resource "aws_security_group" "rds_sg" {
  name        = "linkshrink-rds-sg"
  description = "Allows postgres traffic from ECS service"
  vpc_id      = aws_vpc.main.id
  ingress {
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = [aws_security_group.ecs_service_sg.id]
  }
}
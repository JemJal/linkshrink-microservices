resource "aws_security_group" "alb_sg" {
  name        = "linkshrink-alb-sg"
  description = "Allows web traffic to the ALB"
  vpc_id      = aws_vpc.main.id

  # Allow inbound HTTP traffic from anywhere
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
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

  # Allow inbound traffic from the ALB on port 8000
  ingress {
    protocol        = "tcp"
    from_port       = 8000
    to_port         = 8000
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Allow all outbound traffic (so it can talk to the database and internet)
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

  # Allow inbound postgres traffic ONLY from our ECS service
  ingress {
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = [aws_security_group.ecs_service_sg.id]
  }
}
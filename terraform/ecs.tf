# Get AWS Account ID for building ECR URI
data "aws_caller_identity" "current" {}

# 1. The Application Load Balancer
resource "aws_lb" "main" {
  name               = "linkshrink-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for s in aws_subnet.public : s.id]
}

# 2. The Target Group (a group of targets, our ECS tasks)
resource "aws_lb_target_group" "user_service" {
  name        = "user-service-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path = "/" # Your app should return 200 OK on the root path for health checks
  }
}

# 3. The ALB Listener Rule
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.user_service.arn
  }
}

# 4. The ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "linkshrink-cluster"
}

# 5. The ECS Task Definition
resource "aws_ecs_task_definition" "user_service" {
  family                   = "user-service-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # 0.25 vCPU
  memory                   = "512" # 0.5 GB

  # Role that allows ECS to pull images from ECR
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "user-service"
      # This builds the full ECR image path dynamically
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.eu-north-1.amazonaws.com/user-service:${var.image_tag}"
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
        }
      ]
      environment = [
        {
          name  = "DATABASE_URL"
          value = "postgresql://${aws_db_instance.user_db.username}:${var.db_password}@${aws_db_instance.user_db.address}/${aws_db_instance.user_db.db_name}?sslmode=require"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/user-service"
          "awslogs-region"        = "eu-north-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# IAM Role required by ECS
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Creates the CloudWatch Log Group for our container logs
resource "aws_cloudwatch_log_group" "user_service_logs" {
  name = "/ecs/user-service"
}

# 6. The ECS Service
resource "aws_ecs_service" "user_service" {
  name            = "user-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.user_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [for s in aws_subnet.private : s.id]
    security_groups = [aws_security_group.ecs_service_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.user_service.arn
    container_name   = "user-service"
    container_port   = 8000
  }

  # This helps prevent issues on redeployment
  depends_on = [aws_lb_listener.http]
}
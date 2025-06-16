# terraform/ecs.tf

# Get AWS Account ID for building ECR URI
data "aws_caller_identity" "current" {}

# --- ALB / Load Balancing Resources ---

# 1. The Application Load Balancer
resource "aws_lb" "main" {
  name               = "linkshrink-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

# 2. The Target Group (a group of targets, our ECS tasks)
resource "aws_lb_target_group" "user_service" {
  name        = "user-service-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/"
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

# --- ECS Cluster Resources ---

# 4. The ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "linkshrink-cluster"
}

# 5. The ECS Task Definition
resource "aws_ecs_task_definition" "user_service" {
  family                   = "user-service-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name  = "user-service"
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/user-service:${var.image_tag}"
    portMappings = [{
      containerPort = 8000
    }]
    environment = [{
      name  = "DATABASE_URL"
      value = "postgresql://${aws_db_instance.user_db.username}:${var.db_password}@${aws_db_instance.user_db.address}/${aws_db_instance.user_db.db_name}?sslmode=require"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.user_service_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# 6. The ECS Service
resource "aws_ecs_service" "user_service" {
  name            = "user-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.user_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs_service_sg.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.user_service.arn
    container_name   = "user-service"
    container_port   = 8000
  }
  depends_on = [aws_lb_listener.http]
}

# --- IAM & Logging Resources for ECS ---

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "user_service_logs" {
  name = "/ecs/user-service"
  retention_in_days = 7 # Good practice to set a retention policy
}
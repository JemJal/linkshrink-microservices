# terraform/ecs.tf

# Get AWS Account ID for building ECR URI
data "aws_caller_identity" "current" {}

# --- ALB / Load Balancing Resources ---

resource "aws_lb" "main" {
  name               = "linkshrink-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "user_service" {
  name        = "user-service-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/health" # USING THE CORRECT /health PATH
  }
}

resource "aws_lb_target_group" "link_service" {
  name        = "link-service-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/health"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = jsonencode({ message = "Resource not found" })
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "user_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.user_service.arn
  }
  condition {
    path_pattern {
      values = ["/users*", "/token"]
    }
  }
}

resource "aws_lb_listener_rule" "link_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 90
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.link_service.arn
  }
  condition {
    path_pattern {
      values = ["/links*"]
    }
  }
}

# --- ECS Cluster Resources ---

resource "aws_ecs_cluster" "main" {
  name = "linkshrink-cluster"
}

# Task Definition for the USER-SERVICE
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
    environment = [
      {
        name  = "DATABASE_URL"
        value = "postgresql://${aws_db_instance.user_db.username}:${var.db_password}@${aws_db_instance.user_db.address}:${aws_db_instance.user_db.port}/${aws_db_instance.user_db.db_name}?sslmode=require"
      },
      # =======================================================
      # === THIS IS THE FIX - ADDING THE KEY TO USER-SERVICE ===
      # =======================================================
      {
        name  = "JWT_SECRET_KEY"
        value = var.jwt_secret_key
      }
    ]
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

# Task Definition for the LINK-SERVICE (THIS ONE WAS ALREADY CORRECT)
resource "aws_ecs_task_definition" "link_service" {
  family                   = "link-service-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name  = "link-service"
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/link-service:${var.image_tag}"
    portMappings = [{ containerPort = 8000 }]
    environment = [
      {
        name  = "DATABASE_URL"
        value = "postgresql://${aws_db_instance.link_db.username}:${var.link_db_password}@${aws_db_instance.link_db.address}:${aws_db_instance.link_db.port}/${aws_db_instance.link_db.db_name}?sslmode=require"
      },
      {
        name  = "JWT_SECRET_KEY"
        value = var.jwt_secret_key
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.link_service_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# --- Service, IAM, and Logging Resources ---

resource "aws_ecs_service" "user_service" {
  name            = "user-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.user_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  health_check_grace_period_seconds = 60
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs_service_sg.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.user_service.arn
    container_name   = "user-service"
    container_port   = 8000
  }
  depends_on = [aws_lb_listener_rule.user_service] # Depends on the rule now
}

resource "aws_ecs_service" "link_service" {
  name            = "link-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.link_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  health_check_grace_period_seconds = 60
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs_service_sg.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.link_service.arn
    container_name   = "link-service"
    container_port   = 8000
  }
  depends_on = [aws_lb_listener_rule.link_service] # Depends on the rule now
}

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
  name              = "/ecs/user-service"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "link_service_logs" {
  name              = "/ecs/link-service"
  retention_in_days = 7
}
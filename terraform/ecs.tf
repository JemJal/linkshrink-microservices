# terraform/ecs.tf

# Get AWS Account ID for building ECR URI dynamically
data "aws_caller_identity" "current" {}

# ===================================================================
# ===             1. LOAD BALANCER & ROUTING RESOURCES            ===
# ===================================================================

# This is the single public entry point for our entire application.
resource "aws_lb" "main" {
  name               = "linkshrink-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

# The main listener for our ALB on port 80 (HTTP). It has a default
# action to return a 404 if no specific path rule matches.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = jsonencode({ message = "Endpoint not found" })
      status_code  = "404"
    }
  }
}

# --- Listener Rules: The heart of our API Gateway ---

# Listener RULE for the user-service.
resource "aws_lb_listener_rule" "user_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100 # Highest priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.user_service.arn
  }

  condition {
    path_pattern {
      # FIXED: Added wildcard (*) to match /users, /users/, /users/123, etc.
      values = ["/users*", "/token*"]
    }
  }
}

# Listener RULE for the link-service.
resource "aws_lb_listener_rule" "link_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 90

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.link_service.arn
  }

  condition {
    path_pattern {
      # FIXED: Added wildcard to make this robust as well.
      values = ["/links*"]
    }
  }
}

# Listener RULE for the redirect-service (our catch-all).
# This is our catch-all rule with the lowest priority. All other traffic
# (e.g., short link redirects) will be sent to the redirect-service.
resource "aws_lb_listener_rule" "redirect_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 80 # Lowest priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.redirect_service.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# --- Target Groups: Pools of our backend services ---

resource "aws_lb_target_group" "user_service" {
  name        = "user-service-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/health"
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

resource "aws_lb_target_group" "redirect_service" {
  name        = "redirect-service-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/health"
  }
}

# ===================================================================
# ===               2. ECS CLUSTER & IAM RESOURCES                ===
# ===================================================================

# The logical cluster that will contain all our services.
resource "aws_ecs_cluster" "main" {
  name = "linkshrink-cluster"
}

# A single IAM Role that all our tasks will use. It grants ECS permission
# to pull images from ECR and send logs to CloudWatch.
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ===================================================================
# ===              3. TASK & SERVICE DEFINITIONS                  ===
# ===================================================================

# --- User Service ---

resource "aws_ecs_task_definition" "user_service" {
  family                   = "user-service-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([{
    name  = "user-service"
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/user-service:${var.image_tag}"
    portMappings = [{ containerPort = 8000 }]
    environment = [
      {
        name  = "DATABASE_URL",
        value = "postgresql://${aws_db_instance.user_db.username}:${var.db_password}@${aws_db_instance.user_db.address}:${aws_db_instance.user_db.port}/${aws_db_instance.user_db.db_name}?sslmode=require"
      },
      {
        name  = "JWT_SECRET_KEY",
        value = var.jwt_secret_key
      }
    ]
    logConfiguration = {
      logDriver = "awslogs",
      options   = {
        "awslogs-group"         = aws_cloudwatch_log_group.user_service_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "user_service" {
  name                              = "user-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.user_service.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
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
  depends_on = [aws_lb_listener_rule.user_service]
}

# --- Link Service ---

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
      options   = {
        "awslogs-group"         = aws_cloudwatch_log_group.link_service_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "link_service" {
  name                              = "link-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.link_service.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
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
  depends_on = [aws_lb_listener_rule.link_service]
}

# --- Redirect Service ---

resource "aws_ecs_task_definition" "redirect_service" {
  family                   = "redirect-service-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([{
    name  = "redirect-service"
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/redirect-service:${var.image_tag}"
    portMappings = [{ containerPort = 8000 }]
    environment = [
      {
        name  = "REDIS_HOST"
        value = aws_elasticache_cluster.redis.cache_nodes[0].address
      },
      {
        name  = "RABBITMQ_HOST"
        value = aws_mq_broker.rabbitmq.instances[0].ip_address
      },
      {
        name  = "MQ_USERNAME"
        value = "mqadmin"
      },
      {
        name  = "MQ_PASSWORD"
        value = var.mq_password
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        "awslogs-group"         = aws_cloudwatch_log_group.redirect_service_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "redirect_service" {
  name                              = "redirect-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.redirect_service.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60 # Added grace period
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs_service_sg.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.redirect_service.arn
    container_name   = "redirect-service"
    container_port   = 8000
  }
  depends_on = [aws_lb_listener_rule.redirect_service]
}

# --- CloudWatch Log Groups ---

resource "aws_cloudwatch_log_group" "user_service_logs" {
  name              = "/ecs/user-service"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "link_service_logs" {
  name              = "/ecs/link-service"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "redirect_service_logs" {
  name              = "/ecs/redirect-service"
  retention_in_days = 7
}
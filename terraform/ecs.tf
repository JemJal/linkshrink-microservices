# terraform/ecs.tf

data "aws_caller_identity" "current" {}

# ===================================================================
# ===             1. LOAD BALANCER & ROUTING RESOURCES            ===
# ===================================================================

resource "aws_lb" "main" {
  name               = "linkshrink-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

# --- THE "WEB GUI" SERVICE RESOURCES ---
resource "aws_ecs_task_definition" "web_gui_service" {
  family                   = "web-gui-service-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([{
    name      = "web-gui-service"
    image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/web-gui-service:${var.image_tag}"
    portMappings = [{ containerPort = 80 }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.web_gui_service_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_lb_target_group" "web_gui_service" {
  name        = "web-gui-service-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 2
    interval            = 5
  }
}

resource "aws_ecs_service" "web_gui_service" {
  name            = "web-gui-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web_gui_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs_service_sg.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.web_gui_service.arn
    container_name   = "web-gui-service"
    container_port   = 80
  }
}
# -----------------------------------------------

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_gui_service.arn
  }
}

# --- CORRECTED LISTENER RULES ---
resource "aws_lb_listener_rule" "user_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.user_service.arn
  }
  condition {
    path_pattern {
      values = ["/users*", "/token*"]
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

resource "aws_lb_listener_rule" "redirect_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 80
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.redirect_service.arn
  }
  condition {
    path_pattern {
      values = ["/r/*"]
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

# ECS Cluster & IAM Role (Unchanged)
resource "aws_ecs_cluster" "main" {
  name = "linkshrink-cluster"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs_task_execution_role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }] })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- TASK & SERVICE DEFINITIONS ---

# User Service
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
    portMappings = [{ containerPort = 8000 }]
    environment = [
      { name = "DATABASE_URL", value = "postgresql://${aws_db_instance.user_db.username}:${var.db_password}@${aws_db_instance.user_db.address}:${aws_db_instance.user_db.port}/${aws_db_instance.user_db.db_name}?sslmode=require" },
      { name = "JWT_SECRET_KEY", value = var.jwt_secret_key }
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

# Link Service
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
      { name = "DATABASE_URL", value = "postgresql://${aws_db_instance.link_db.username}:${var.link_db_password}@${aws_db_instance.link_db.address}:${aws_db_instance.link_db.port}/${aws_db_instance.link_db.db_name}?sslmode=require" },
      { name = "JWT_SECRET_KEY", value = var.jwt_secret_key },
      { name = "BASE_URL", value = "http://${aws_lb.main.dns_name}" }
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

# Redirect Service
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
      { name = "REDIS_HOST", value = aws_elasticache_cluster.redis.cache_nodes[0].address },
      { name = "RABBITMQ_HOST", value = aws_mq_broker.rabbitmq.instances[0].ip_address },
      { name = "MQ_USERNAME", value = "mqadmin" },
      { name = "MQ_PASSWORD", value = var.mq_password },
      { name = "LINK_SERVICE_URL", value = "http://${aws_lb.main.dns_name}" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
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
  health_check_grace_period_seconds = 60
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
resource "aws_cloudwatch_log_group" "web_gui_service_logs" {
  name              = "/ecs/web-gui-service"
  retention_in_days = 7
}
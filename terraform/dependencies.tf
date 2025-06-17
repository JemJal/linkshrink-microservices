# terraform/dependencies.tf

# --- RabbitMQ (Amazon MQ) Resources ---

resource "aws_security_group" "mq_sg" {
  name        = "linkshrink-mq-sg"
  description = "Allow access to the MQ broker"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "linkshrink-mq-sg" }

  ingress {
    protocol        = "tcp"
    from_port       = 5671
    to_port         = 5671
    security_groups = [aws_security_group.ecs_service_sg.id]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
}

resource "aws_mq_broker" "rabbitmq" {
  broker_name                = "linkshrink-rabbitmq"
  engine_type                = "RabbitMQ"
  engine_version             = "3.13"
  host_instance_type         = "mq.t3.micro"
  deployment_mode            = "SINGLE_INSTANCE"
  publicly_accessible        = false
  subnet_ids                 = [aws_subnet.private[0].id]
  security_groups            = [aws_security_group.mq_sg.id]
  auto_minor_version_upgrade = true
  user {
    username = "mqadmin"
    password = var.mq_password
  }
}

# ===================================================================
# === THIS IS THE MISSING PART - ADD EVERYTHING BELOW THIS LINE ===
# ===================================================================

# --- Redis (ElastiCache) Resources ---

resource "aws_security_group" "redis_sg" {
  name        = "linkshrink-redis-sg"
  description = "Allow access to the Redis cluster from ECS"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "linkshrink-redis-sg" }

  ingress {
    protocol        = "tcp"
    from_port       = 6379
    to_port         = 6379
    security_groups = [aws_security_group.ecs_service_sg.id]
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "linkshrink-redis-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "linkshrink-redis-cluster"
  engine               = "redis"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis_sg.id]
}
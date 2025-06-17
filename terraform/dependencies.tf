# In terraform/dependencies.tf

# --- RabbitMQ (Amazon MQ) Resources ---

resource "aws_security_group" "mq_sg" {
  name        = "linkshrink-mq-sg"
  description = "Allow access to the MQ broker"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "linkshrink-mq-sg" }

  # Ingress (Rule 1): Allows ECS tasks to connect on the main AMQP port.
  ingress {
    protocol        = "tcp"
    from_port       = 5671 # RabbitMQ's secure AMQPS port
    to_port         = 5671
    security_groups = [aws_security_group.ecs_service_sg.id]
  }

  # Ingress (Rule 2): Allows access to RabbitMQ console from WITHIN our VPC
  # This is more secure than opening it to the world. We can access it later
  # using a "bastion host" or other secure methods.
  ingress {
    protocol   = "tcp"
    from_port  = 443 # The new private endpoint console port is 443
    to_port    = 443
    cidr_blocks = [aws_vpc.main.cidr_block] # Only allow access from our VPC's IP range
  }
}

resource "aws_mq_broker" "rabbitmq" {
  broker_name        = "linkshrink-rabbitmq"
  engine_type        = "RabbitMQ"
  engine_version     = "3.13"
  host_instance_type = "mq.t3.micro"
  deployment_mode    = "SINGLE_INSTANCE"
  
  # --- THE FIX ---
  # Make the broker private and let it be controlled by Security Groups
  publicly_accessible = false 
  
  # Place the broker's network interfaces in our private subnets
  subnet_ids          = [aws_subnet.private[0].id] 
  
  # Associate the security group with the broker's network interface
  security_groups     = [aws_security_group.mq_sg.id]
  
  auto_minor_version_upgrade = true
  
  user {
    username = "mqadmin"
    password = var.mq_password
  }
}
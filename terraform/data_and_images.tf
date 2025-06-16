# 1. ECR Repository for the user-service
resource "aws_ecr_repository" "user_service" {
  name = "user-service"
}

# 2. Database Subnet Group (tells RDS which subnets it can live in)
resource "aws_db_subnet_group" "main" {
  name       = "linkshrink-db-subnet-group"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

# 3. The PostgreSQL RDS instance
resource "aws_db_instance" "user_db" {
  identifier           = "user-db-instance"
  instance_class       = "db.t3.micro" # Free-tier eligible
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "15.7"
  username             = "dbuser"
  password             = var.db_password # Using our secure variable
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true
  publicly_accessible  = false # Best practice: DB is not on public internet
}
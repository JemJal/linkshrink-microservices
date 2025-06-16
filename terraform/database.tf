# terraform/database.tf

# 1. Database Subnet Group (tells RDS which subnets it can live in)
resource "aws_db_subnet_group" "main" {
  name       = "linkshrink-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name = "linkshrink-db-subnet-group"
  }
}

# 2. The PostgreSQL RDS instance
resource "aws_db_instance" "user_db" {
  identifier           = "user-db-instance"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "15.7"
  username             = "dbuser"
  password             = var.db_password
  db_name              = "user_service_db" # Added a specific DB name
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true
  publicly_accessible  = false
}

resource "aws_db_instance" "link_db" {
  identifier           = "link-db-instance" # A unique name
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "15.7" # Use the same version as before
  username             = "linkdbuser" # A different username
  password             = var.link_db_password # Using the new variable
  db_name              = "link_db" # The name of the database inside the instance
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true
  publicly_accessible  = false
}
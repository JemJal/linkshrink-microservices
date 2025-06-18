# terraform/network.tf

# 1. The Virtual Private Cloud (VPC)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "linkshrink-vpc"
  }
}

# Provider for Availability Zones
data "aws_availability_zones" "available" {}

# 2. Public Subnets (for Load Balancer and NAT Gateway)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "linkshrink-public-subnet-${count.index + 1}"
  }
}

# 3. Private Subnets (for ECS tasks and Database)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 101}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "linkshrink-private-subnet-${count.index + 1}"
  }
}

# 4. Internet Gateway (to allow traffic to/from the internet for public subnets)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "linkshrink-igw"
  }
}

# 5. Route Table for Public Subnets (points to Internet Gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "linkshrink-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ================= NAT GATEWAY =================
# A NAT Gateway allows services in a PRIVATE subnet to access the internet
# for things like downloading OS updates or external APIs, without being
# accessible FROM the internet. This is a best practice.

# 6. Elastic IP for the NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.main]
}

# 7. The NAT Gateway itself (placed in a public subnet)
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # Place it in the first public subnet
  tags = {
    Name = "linkshrink-nat-gateway"
  }
  depends_on = [aws_eip.nat]
}

# 8. Route Table for Private Subnets (points to NAT Gateway)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = {
    Name = "linkshrink-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

data "aws_route53_zone" "parent" {
  name = var.parent_zone_name
}
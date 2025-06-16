# 1. The Virtual Private Cloud (VPC)
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "linkshrink-vpc"
  }
}

# 2. Public Subnets (for our Load Balancer)
resource "aws_subnet" "public" {
  count             = 2 # Create two for high availability across Availability Zones
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "linkshrink-public-subnet-${count.index + 1}"
  }
}

# 3. Private Subnets (for our ECS tasks and Database)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 101}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "linkshrink-private-subnet-${count.index + 1}"
  }
}

data "aws_availability_zones" "available" {}

# 4. Internet Gateway (to allow traffic to/from the internet)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "linkshrink-igw"
  }
}

# 5. Route Table for Public Subnets
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
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
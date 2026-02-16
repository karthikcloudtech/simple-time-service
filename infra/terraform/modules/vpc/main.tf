resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.environment != "" ? "${var.project_name}-vpc-${var.environment}" : "${var.project_name}-vpc"
  }

}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index % length(var.availability_zones)]
  map_public_ip_on_launch = true
  tags = merge(
    { Name = "${var.project_name}-public-subnet-${count.index + 1}" },
    var.eks_cluster_name != "" ? {
      "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
      "kubernetes.io/role/elb" = "1"
    } : {}
  )

}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  cidr_block = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index % length(var.availability_zones)]
  tags = merge(
    { Name = "${var.project_name}-private-subnet-${count.index + 1}" },
    var.eks_cluster_name != "" ? {
      "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
      "kubernetes.io/role/internal-elb" = "1"
    } : {}
  )
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat-gw"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)
  subnet_id = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# VPC Peering with Default VPC
data "aws_vpc" "default" {
  default = true
}

resource "aws_vpc_peering_connection" "main_to_default" {
  vpc_id      = aws_vpc.main.id
  peer_vpc_id = data.aws_vpc.default.id

  tags = {
    Name = "${var.project_name}-peering-default"
  }
}

resource "aws_vpc_peering_connection_accepter" "default" {
  vpc_peering_connection_id = aws_vpc_peering_connection.main_to_default.id
  auto_accept              = true

  tags = {
    Name = "${var.project_name}-peering-default-accepter"
  }
}

# Get default VPC main route table
data "aws_route_table" "default" {
  vpc_id = data.aws_vpc.default.id
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

# Route from main VPC public subnets to default VPC
resource "aws_route" "public_to_default" {
  route_table_id            = aws_route_table.public.id
  destination_cidr_block    = data.aws_vpc.default.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.main_to_default.id

  depends_on = [aws_vpc_peering_connection_accepter.default]
}

# Route from main VPC private subnets to default VPC
resource "aws_route" "private_to_default" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = data.aws_vpc.default.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.main_to_default.id

  depends_on = [aws_vpc_peering_connection_accepter.default]
}

# Route from default VPC back to main VPC
resource "aws_route" "default_to_main" {
  route_table_id            = data.aws_route_table.default.id
  destination_cidr_block    = var.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main_to_default.id

  depends_on = [aws_vpc_peering_connection_accepter.default]
}

### メインVPC作成 ###
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

# Internet Gateway作成
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# Public Subnet作成
resource "aws_subnet" "public_subnets" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

# Public Route Table作成
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Public Subnetとの関連付け
resource "aws_route_table_association" "public_subnet_associations" {
  count          = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway作成
resource "aws_nat_gateway" "nat_gateways" {
  count         = 2
  allocation_id = aws_eip.nat_gateways[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id

  tags = {
    Name = "nat-gw-${count.index + 1}"
  }
}

# Private Subnet作成
resource "aws_subnet" "private_subnets" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 2)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

# Private Route Table作成
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateways[count.index].id
  }

  tags = {
    Name = "private-route-table-${count.index + 1}"
  }
}

# Private Subnetとの関連付け
resource "aws_route_table_association" "private_subnet_associations" {
  count          = 2
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# サービスエンドポイントの作成
resource "aws_vpc_endpoint_service" "nlb_service" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.nlb.arn]

  allowed_principals = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]
}

### PrivateLink用VPC作成 ###
resource "aws_vpc" "privatelink" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "privatelink-vpc"
  }
}

# PrivateLink用Subnet作成
resource "aws_subnet" "privatelink_subnets" {
  count                   = 2
  vpc_id                  = aws_vpc.privatelink.id
  cidr_block              = cidrsubnet(aws_vpc.privatelink.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "privatelink-subnet-${count.index + 1}"
  }
}

# VPCエンドポイント作成
resource "aws_vpc_endpoint" "privatelink_endpoint" {
  vpc_id            = aws_vpc.privatelink.id
  service_name      = aws_vpc_endpoint_service.nlb_service.service_name
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.privatelink_sg.id
  ]

  subnet_ids = aws_subnet.privatelink_subnets[*].id

  private_dns_enabled = false
}

# VPCエンドポイントSecurityGroup作成
resource "aws_security_group" "privatelink_sg" {
  name        = "privatelink-sg"
  vpc_id      = aws_vpc.privatelink.id
  description = "Security group for VPC Endpoint"

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = [aws_vpc.test.cidr_block]
    description     = "Allow all traffic from VPC"
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    description     = "Allow all outbound traffic"
  }

  tags = {
    Name = "privatelink-sg"
  }
}

### 検証用VPC作成 ###
resource "aws_vpc" "test" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "test-vpc"
  }
}

# 検証用Private Subnet作成
resource "aws_subnet" "test_private_subnets" {
  count                   = 2
  vpc_id                  = aws_vpc.test.id
  cidr_block              = cidrsubnet(aws_vpc.test.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "test-private-subnet-${count.index + 1}"
  }
}

# VPCピアリング接続作成
resource "aws_vpc_peering_connection" "privatelink_test_peering" {
  peer_vpc_id   = aws_vpc.test.id
  vpc_id        = aws_vpc.privatelink.id
  auto_accept   = true
  tags = {
    Name = "privatelink-test-peering"
  }
}

# VPCピアリングルート作成 (privatelink -> test)
resource "aws_route" "privatelink_to_test" {
  route_table_id            = aws_vpc.privatelink.default_route_table_id
  destination_cidr_block    = aws_vpc.test.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.privatelink_test_peering.id
}

# VPCピアリングルート作成 (test -> privatelink)
resource "aws_route" "test_to_privatelink" {
  route_table_id            = aws_vpc.test.default_route_table_id
  destination_cidr_block    = aws_vpc.privatelink.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.privatelink_test_peering.id
}

# EC2 Instance Connect Endpoint用 Security Group作成
resource "aws_security_group" "bastion_eci" {
  vpc_id = aws_vpc.test.id
  name   = "bastion_for_eci_allow_ssh"
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance Connect Endpoint
resource "aws_ec2_instance_connect_endpoint" "for_bastion_eic" {
  subnet_id          = aws_subnet.test_private_subnets[0].id
  security_group_ids = [aws_security_group.bastion_eci.id]
  preserve_client_ip = true
}
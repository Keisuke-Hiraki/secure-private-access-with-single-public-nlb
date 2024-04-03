# プロバイダー設定
provider "aws" {
  region = "ap-northeast-1" # 適切なリージョンを指定してください
}

# データソース
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "amazon_linux_2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_caller_identity" "current" {}

# メインVPC作成
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
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

# Internet Gateway作成
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
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

# Elastic IP作成
resource "aws_eip" "nat_gateways" {
  count  = 2
  domain = "vpc"

  tags = {
    Name = "nat-gw-eip-${count.index + 1}"
  }
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

# EC2 Security Group作成
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  vpc_id      = aws_vpc.main.id
  description = "Security group for EC2 instances"

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    description     = "Allow all outbound traffic"
  }

  tags = {
    Name = "ec2-sg"
  }
}

# EC2用セキュリティグループのインバウンドへNLBのセキュリティグループをソースに指定
resource "aws_security_group_rule" "sg_ec2_rule" {
  type                     = "ingress"
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nlb_sg.id
  from_port                = 80
  security_group_id        = aws_security_group.ec2_sg.id
}

# EC2 Instance作成
resource "aws_instance" "ec2_instances" {
  count                  = 2
  ami                    = data.aws_ssm_parameter.amazon_linux_2023_ami.value
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnets[count.index].id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data              = <<-EOF
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from $(hostname)</h1>" > /var/www/html/index.html
  EOF

  tags = {
    Name = "ec2-instance-${count.index + 1}"
  }
}

# NLB用Security Group作成
resource "aws_security_group" "nlb_sg" {
  name        = "test-sg-nlb"
  description = "Allow http from NLB"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
  egress {
    cidr_blocks = [
      "0.0.0.0/0",
    ]
    from_port = 80
    protocol  = "tcp"
    to_port   = 80
  }
}

# Network Load Balancer作成
resource "aws_lb" "nlb" {
  name               = "nlb"
  load_balancer_type = "network"
  subnets            = aws_subnet.public_subnets[*].id
  security_groups    = [aws_security_group.nlb_sg.id]
  tags = {
    Name = "nlb"
  }
}

# Target Group作成
resource "aws_lb_target_group" "nlb_tg" {
  name        = "nlb-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    interval            = 30
    port                = 80
    protocol            = "TCP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# EC2インスタンスをTarget Groupに登録
resource "aws_lb_target_group_attachment" "nlb_tg_attachments" {
  count            = 2
  target_group_arn = aws_lb_target_group.nlb_tg.arn
  target_id        = aws_instance.ec2_instances[count.index].id
  port             = 80
}

# Listenerの作成
resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_tg.arn
  }
}

# サービスエンドポイントの作成
resource "aws_vpc_endpoint_service" "nlb_service" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.nlb.arn]

  allowed_principals = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]
}

# PrivateLink用VPC作成
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
    cidr_blocks     = [aws_vpc.privatelink.cidr_block]
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

# 検証用VPC作成
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

# 検証用EC2 Security Group作成
resource "aws_security_group" "test_ec2_sg" {
  name        = "test-ec2-sg"
  vpc_id      = aws_vpc.test.id
  description = "Security group for test EC2 instances"

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_eci.id]
    description     = "Allow SSH from anywhere"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    description     = "Allow all outbound traffic"
  }

  tags = {
    Name = "test-ec2-sg"
  }
}

# 検証用EC2 Instance作成
resource "aws_instance" "test_ec2_instance" {
  ami                    = data.aws_ssm_parameter.amazon_linux_2023_ami.value
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.test_private_subnets[0].id
  vpc_security_group_ids = [aws_security_group.test_ec2_sg.id]

  tags = {
    Name = "test-ec2-instance"
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
# Elastic IP作成
resource "aws_eip" "nat_gateways" {
  count = 2
  domain   = "vpc"

  tags = {
    Name = "nat-gw-eip-${count.index + 1}"
  }
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
  vpc_id      = aws_vpc.main.id

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
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
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
#-------------------------------------------------
#~~~~~~~~~~ Providers
#-------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "eu-central-1"
}

#-------------------------------------------------
#~~~~~~~~~~ Variables
#-------------------------------------------------

variable "key" {
  description = "SSH Key"
  type        = string
  default     = "amazon"
}

variable "db_name" {
  description = "RDS DB name"
  type        = string
  default     = "wordpressdb"
}

variable "db_user" {
  description = "RDS DB username"
  type        = string
  default     = "wordpress"
}

variable "db_password" {
  description = "RDS DB password"
  type        = string
  default     = "Qwerty12345-"
}

#-------------------------------------------------
#~~~~~~~~~~ AMI Images
#-------------------------------------------------

data "aws_ami" "ecs" {
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-2.0.*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  owners = ["amazon"]
}

#-------------------------------------------------
#~~~~~~~~~~ IAM Roles
#-------------------------------------------------

data "aws_iam_policy_document" "instance" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  depends_on = [data.aws_iam_policy_document.instance]

  name               = "instance"
  assume_role_policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_role_policy_attachment" "instance" {
  depends_on = [aws_iam_role.instance]

  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "instance" {
  depends_on = [aws_iam_role.instance]

  name = "instance"
  role = aws_iam_role.instance.id
}

#-------------------------------------------------
#~~~~~~~~~~ Main
#-------------------------------------------------

resource "aws_vpc" "main" {
  depends_on = []

  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "main" {
  depends_on = [aws_vpc.main]

  vpc_id = aws_vpc.main.id
}

resource "aws_security_group" "main" {
  depends_on = [aws_vpc.main]

  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_route_table" "main" {
  depends_on = [aws_internet_gateway.main]

  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_main_route_table_association" "main" {
  depends_on = [aws_route_table.main, aws_vpc.main]

  route_table_id = aws_route_table.main.id
  vpc_id         = aws_vpc.main.id
}

#-------------------------------------------------
#~~~~~~~~~~ Subnets
#-------------------------------------------------

resource "aws_subnet" "sub1" {
  depends_on = [aws_vpc.main]

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-central-1a"
}

resource "aws_subnet" "sub2" {
  depends_on = [aws_vpc.main]

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1b"
}

resource "aws_subnet" "sub3" {
  depends_on = [aws_vpc.main]

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-central-1c"
}

#-------------------------------------------------
#~~~~~~~~~~ MySQL
#-------------------------------------------------

resource "aws_db_subnet_group" "mysql" {
  depends_on = [aws_subnet.sub1, aws_subnet.sub2, aws_subnet.sub3]

  subnet_ids = [aws_subnet.sub1.id, aws_subnet.sub2.id, aws_subnet.sub3.id]
}

resource "aws_db_instance" "mysql" {
  depends_on = [aws_security_group.main, aws_db_subnet_group.mysql]

  allocated_storage = 5
  engine            = "mysql"
  engine_version    = "5.7"
  instance_class    = "db.t2.micro"

  name     = var.db_name
  username = var.db_user
  password = var.db_password

  port                   = "3306"
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.mysql.id
  vpc_security_group_ids = [aws_security_group.main.id]
  skip_final_snapshot    = true
}

#-------------------------------------------------
#~~~~~~~~~~ Wordpress
#-------------------------------------------------

resource "aws_ecs_cluster" "wordpress" {
  depends_on = []

  name = "wordpress"
}

resource "aws_lb" "wordpress" {
  depends_on = [aws_subnet.sub1, aws_subnet.sub2, aws_subnet.sub3, aws_security_group.main]

  name            = "wordpress"
  subnets         = [aws_subnet.sub1.id, aws_subnet.sub2.id, aws_subnet.sub3.id]
  security_groups = [aws_security_group.main.id]
}

resource "aws_lb_target_group" "wordpress" {
  depends_on = [aws_vpc.main]

  name        = "wordpress"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
}

resource "aws_lb_listener" "wordpress" {
  depends_on = [aws_lb.wordpress, aws_lb_target_group.wordpress]

  load_balancer_arn = aws_lb.wordpress.id
  port              = 80
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.wordpress.id
    type             = "forward"
  }
}

resource "aws_ecs_service" "wordpress" {
  depends_on = [aws_ecs_cluster.wordpress, aws_ecs_task_definition.wordpress, aws_lb_target_group.wordpress]

  name                              = "wordpress"
  cluster                           = aws_ecs_cluster.wordpress.id
  task_definition                   = aws_ecs_task_definition.wordpress.arn
  desired_count                     = 1
  launch_type                       = "EC2"
  health_check_grace_period_seconds = "300"

  load_balancer {
    target_group_arn = aws_lb_target_group.wordpress.id
    container_name   = "wordpress"
    container_port   = 80
  }
}

resource "aws_ecs_task_definition" "wordpress" {
  depends_on = [aws_db_instance.mysql, var.db_name, var.db_user, var.db_password]

  family                   = "wordpress"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]

  container_definitions = templatefile("wordpress.json", {
    db_host     = aws_db_instance.mysql.endpoint,
    db_name     = var.db_name,
    db_user     = var.db_user,
    db_password = var.db_password,
  })

  cpu    = 1024
  memory = 700
}

resource "aws_autoscaling_group" "wordpress" {
  depends_on = [aws_subnet.sub1, aws_subnet.sub2, aws_subnet.sub3]

  name                 = "wordpress"
  max_size             = 1
  min_size             = 1
  desired_capacity     = 1
  vpc_zone_identifier  = [aws_subnet.sub1.id, aws_subnet.sub2.id, aws_subnet.sub3.id]
  launch_configuration = aws_launch_configuration.wordpress.name
  health_check_type    = "ELB"
}

output "address" {
  depends_on = [aws_lb.wordpress]

  description = "Address to access the application"
  value       = "http://${aws_lb.wordpress.dns_name}/wp-admin/install.php"
}

resource "aws_launch_configuration" "wordpress" {
  depends_on = [
    aws_ecs_cluster.wordpress,
    aws_iam_instance_profile.instance,
    aws_security_group.main,
    data.aws_ami.ecs,
    var.key
  ]

  name                 = "wordpress"
  image_id             = data.aws_ami.ecs.id
  instance_type        = "t2.micro"
  iam_instance_profile = aws_iam_instance_profile.instance.id

  lifecycle {
    create_before_destroy = true
  }

  security_groups             = [aws_security_group.main.id]
  associate_public_ip_address = true
  key_name                    = var.key
  user_data                   = <<EOF
                                  #!/bin/bash
                                  sudo yum update -y
                                  echo ECS_CLUSTER=${aws_ecs_cluster.wordpress.id} >> /etc/ecs/ecs.config
                                  EOF
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}
/*
# create default vpc if one does not exit
resource "aws_default_vpc" "default_vpc" {
}
*/


  # Create Web Security Group
resource "aws_security_group" "web-sg" {
  name        = "docker-Web-SG"
  description = "Allow ssh and http inbound traffic"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
      description = "ingress port "
      #from_port   = ingress.value
      from_port   = 8000
      to_port     = 8100
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    
  }
  ingress {
      description = "ingress 22 port "
      #from_port   = ingress.value
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "docker-Web-SG"
  }
}
resource "aws_security_group" "ecs-sg" {
  name        = "Ecs-Web-SG"
  description = "Allow ssh and http inbound traffic"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
      description = "ingress port "
      #from_port   = ingress.value
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      security_groups = [ aws_security_group.lb-sg.id ]
    
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Ecs-Web-SG"
  }
}
resource "aws_security_group" "lb-sg" {
  name        = "lb-Web-SG"
  description = "Allow http inbound traffic"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
      description = "ingress port "
      #from_port   = ingress.value
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    
  }
  ingress {
      description = "ingress port "
      #from_port   = ingress.value
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lb-Web-SG"
  }
}
  
# Generates a secure private k ey and encodes it as PEM
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}
# Create the Key Pair
resource "aws_key_pair" "ec2_key" {
  key_name   = "docker-keypair"  
  public_key = tls_private_key.ec2_key.public_key_openssh
}
# Save file
resource "local_file" "ssh_key" {
  filename = "${aws_key_pair.ec2_key.key_name}.pem"
  content  = tls_private_key.ec2_key.private_key_pem
  file_permission = "400"
}

resource "aws_iam_instance_profile" "profile1" {
  name = "ec2iamprofile"
  role = aws_iam_role.ec2-admin_role.name
}
#create ec2 instances 

resource "aws_instance" "DockerInstance" {
  ami                    = data.aws_ami.amazon-2.id
  instance_type          = "t2.medium"
  vpc_security_group_ids = [aws_security_group.web-sg.id]
  key_name               = aws_key_pair.ec2_key.key_name
  #user_data              = file("install.sh")
  subnet_id = aws_subnet.public1.id
  iam_instance_profile = aws_iam_instance_profile.profile1.name
  associate_public_ip_address = true
  root_block_device {
    volume_size = 30  
    volume_type = "gp2"  
  }
  tags = {
    Name = "docker-instance"
  }
 
}
resource "aws_ecr_repository" "repo1" {
  name                 = "devops"
 force_delete = true
}



resource "null_resource" "name1" {
  connection {
    host = aws_instance.DockerInstance.public_ip
    private_key = file(local_file.ssh_key.filename)
    user = "ec2-user"
    type = "ssh"
  }
  provisioner "remote-exec" {
    inline = [
        "sudo yum update -y",
       " sudo yum install docker -y",
        "sudo usermod -aG docker ec2-user",
        "sudo service docker start",
        "sudo systemctl enable docker ",
        "sudo yum install git -y",
        "sudo yum install wget -y",
        "sudo curl -L https://github.com/docker/compose/releases/download/1.20.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose",
        "sudo chmod +x /usr/local/bin/docker-compose", 
        "git clone https://github.com/utrains/static-app.git",
        "cd static-app",
        "sudo docker build -t webapp .",
        "aws ecr get-login-password --region us-east-1 |sudo docker login --username AWS --password-stdin ${aws_ecr_repository.repo1.repository_url}",
        "sudo docker tag webapp ${aws_ecr_repository.repo1.repository_url}:dev",
        "sudo docker push ${aws_ecr_repository.repo1.repository_url}:dev",
     ]
  }
  depends_on = [ aws_instance.DockerInstance,aws_ecr_repository.repo1 ]
}

resource "aws_ecs_cluster" "my_cluster" {
  name = "my-ecs-cluster"
}

resource "aws_ecs_service" "my_service" {
  name            = "my-ecs-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.my_task_definition.arn
  launch_type     = "FARGATE"
  desired_count   = 2
  

  network_configuration {
    subnets = [aws_subnet.private1.id,aws_subnet.private2.id] 
    security_groups = [aws_security_group.ecs-sg.id] 
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.my_target_group.arn
    container_name   = "my-container"
    container_port   = 80
  }

  depends_on = [aws_lb.my_load_balancer, null_resource.name1]
}

resource "aws_ecs_task_definition" "my_task_definition" {
  family                   = "my-task-family"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([
    {
      name  = "my-container"
      image = "${aws_ecr_repository.repo1.repository_url}:dev"
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  inline_policy {
    name = "ECRTaskExecutionPolicy"

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action = [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetAuthorizationToken"
          ],
          Effect   = "Allow",
          Resource = "*"
        }
      ]
    })
  }
}
resource "aws_iam_role" "ec2-admin_role" {
  name = "adminrole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "admin_role_attachment" {
  role       = aws_iam_role.ec2-admin_role.name
  policy_arn = data.aws_iam_policy.admin_policy.arn
}
resource "aws_lb" "my_load_balancer" {
  name               = "my-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb-sg.id] 
  subnets            = [aws_subnet.public1.id, aws_subnet.public2.id] 

  enable_deletion_protection = false
}

resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
resource "aws_lb_listener" "my_listener1" {
  load_balancer_arn = aws_lb.my_load_balancer.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn = data.aws_acm_certificate.issued.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
}
}

# resource "aws_lb_listener_certificate" "my_cert" {
#   listener_arn    = aws_lb_listener.my_listener1.arn
#   certificate_arn = data.aws_acm_certificate.issued.arn
# }

resource "aws_lb_target_group" "my_target_group" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = aws_vpc.vpc1.id 
}

resource "aws_route53_record" "www" {
  zone_id = "Z0889945UE3027Z54R69"
  name    = "app1.utrains.info"
  type    = "A"

  alias {
    name                   = aws_lb.my_load_balancer.dns_name
    zone_id                = aws_lb.my_load_balancer.zone_id
    evaluate_target_health = true
  }
}
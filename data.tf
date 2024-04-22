#data for amazon linux

data "aws_ami" "amazon-2" {
    most_recent = true
  
    filter {
      name = "name"
      values = ["amzn2-ami-hvm-*-x86_64-ebs"]
    }
    owners = ["amazon"]
  }
 data "aws_acm_certificate" "issued" {
  domain   = "*.utrains.info"
  statuses = ["ISSUED"]
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "subs" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
    filter {
    name   = "availability-zone"
    values = ["us-east-1a"] 
  }
}
data "aws_subnet" "subs1" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
    filter {
    name   = "availability-zone"
    values = ["us-east-1b"] 
  }
}
data "aws_iam_policy" "admin_policy" {
  arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

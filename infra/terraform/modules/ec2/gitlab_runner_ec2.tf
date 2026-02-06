provider "aws" {
  region = "us-east-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_security_group" "default" {
  name   = "default"
  vpc_id = data.aws_vpc.default.id
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
    filter {
    name   = "availability-zone"
    values = ["us-east-1a"]
  }
}


resource "aws_instance" "gitlab_runner_spot_instance" {
  ami                         = "ami-00ac61dcca1e166d0"
  instance_type               = "m7i-flex.large"
  subnet_id                   = data.aws_subnets.public.ids[0]
  vpc_security_group_ids      = [data.aws_security_group.default.id]
  associate_public_ip_address = true
  key_name                    = "us_east"
  tags = {
    Name = "gitlab_runner_spot_instance"
  }
}

terraform {
  backend "s3" {
    bucket      = "simple-time-service-tf-state-prod"
    key         = "ec2/terraform.tfstate"
    region      = "us-east-1"
    use_lockfile = true
    encrypt     = true
  }
}

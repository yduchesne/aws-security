locals {
  availability_zone = sort(data.aws_availability_zones.available.names)[0]
}

resource "aws_vpc" "dev_lab" {
  provider = aws.dev

  # checkov:skip=CKV2_AWS_11: VPC flow logs would require a separate persistent log destination and are outside this minimal, destructible exercise-egress foundation; CloudTrail records the exercise API activity.
  cidr_block           = var.dev_lab_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "DevLabExerciseVpc"
    Purpose = "LabExercises"
  }

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.dev.account_id == var.lab_account_ids.dev
      error_message = "The dev provider must assume into the configured Dev Lab account."
    }

    precondition {
      condition     = var.management_account_id != var.lab_account_ids.dev && var.management_account_id != var.lab_account_ids.test
      error_message = "The management, Dev Lab, and Test Lab accounts must be distinct."
    }
  }
}

resource "aws_default_security_group" "dev_lab" {
  provider = aws.dev
  vpc_id   = aws_vpc.dev_lab.id

  ingress = []
  egress  = []

  tags = {
    Name    = "DevLabExerciseVpcDefaultDeny"
    Purpose = "LabExercises"
  }
}

resource "aws_internet_gateway" "dev_lab" {
  provider = aws.dev
  vpc_id   = aws_vpc.dev_lab.id

  tags = {
    Name    = "DevLabExerciseInternetGateway"
    Purpose = "LabExercises"
  }
}

resource "aws_subnet" "dev_lab_public" {
  provider = aws.dev

  # checkov:skip=CKV_AWS_130: This is the explicit public egress subnet for short-lived no-ingress lab instances; no NAT gateway is created.
  vpc_id                  = aws_vpc.dev_lab.id
  cidr_block              = var.dev_lab_public_subnet_cidr
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name    = "DevLabExercisePublicSubnet"
    Purpose = "LabExercises"
    Network = "Public"
  }
}

resource "aws_route_table" "dev_lab_public" {
  provider = aws.dev
  vpc_id   = aws_vpc.dev_lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev_lab.id
  }

  tags = {
    Name    = "DevLabExercisePublicRouteTable"
    Purpose = "LabExercises"
    Network = "Public"
  }
}

resource "aws_route_table_association" "dev_lab_public" {
  provider = aws.dev

  subnet_id      = aws_subnet.dev_lab_public.id
  route_table_id = aws_route_table.dev_lab_public.id
}

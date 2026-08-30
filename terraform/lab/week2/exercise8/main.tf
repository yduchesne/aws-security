# Curriculum: Core
locals {
  role_path         = "/week2/exercise8/"
  boundary_arn      = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  bucket_name       = "${var.lab_bucket_name_prefix}exercise8-${var.source_account_id}"
  discovered_ami    = try(data.aws_ami.amazon_linux_2023[0].id, "")
  effective_ami     = var.ami_id != null ? var.ami_id : local.discovered_ami
  discovered_subnet = try(sort(data.aws_subnets.lab_foundation[0].ids)[0], "")
  effective_subnet  = var.subnet_id != null ? var.subnet_id : local.discovered_subnet
}

data "aws_iam_policy" "lab_role_boundary" {
  arn = local.boundary_arn
}

data "aws_ami" "amazon_linux_2023" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_subnets" "lab_foundation" {
  count = var.subnet_id == null ? 1 : 0

  filter {
    name   = "tag:Purpose"
    values = ["LabExercises"]
  }

  filter {
    name   = "tag:Network"
    values = ["Public"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_subnet" "selected" {
  id = local.effective_subnet
}

resource "aws_s3_bucket" "exercise" {
  # checkov:skip=CKV_AWS_18: This short-lived workload-identity fixture contains only nonsensitive test strings; the separate lab trail captures object data events.
  # checkov:skip=CKV_AWS_144: Cross-Region replication is disproportionate for a disposable exercise bucket and would leave resources outside this state.
  # checkov:skip=CKV2_AWS_62: Event notifications are unrelated to the workload-identity control under test.
  # checkov:skip=CKV2_AWS_61: The versioned bucket is force-destroyed with the short-lived exercise; lifecycle expiration would not improve the intended retention.
  # checkov:skip=CKV_AWS_145: SSE-S3 protects nonsensitive fixture data and avoids adding KMS permissions to the bounded EC2 workload role.
  bucket        = local.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "exercise" {
  bucket = aws_s3_bucket.exercise.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "exercise" {
  bucket = aws_s3_bucket.exercise.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "exercise" {
  bucket = aws_s3_bucket.exercise.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "allowed" {
  bucket  = aws_s3_bucket.exercise.id
  key     = "exercise8/allowed.txt"
  content = "EC2 instance-profile access succeeded."

  depends_on = [aws_s3_bucket_versioning.exercise]
}

resource "aws_s3_object" "denied" {
  bucket  = aws_s3_bucket.exercise.id
  key     = "exercise8/denied.txt"
  content = "The EC2 role must not read this object."

  depends_on = [aws_s3_bucket_versioning.exercise]
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise8Role"
  path                 = local.role_path
  description          = "Bounded EC2 workload role for the native temporary-credential exercise."
  permissions_boundary = data.aws_iam_policy.lab_role_boundary.arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEC2WorkloadIdentity"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "exercise" {
  role = aws_iam_role.exercise.id
  name = "Exercise8ReadOnlyApprovedObject"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadCurrentIdentity"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
      {
        Sid      = "ReadOnlyApprovedObject"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = aws_s3_object.allowed.arn
      },
    ]
  })
}

resource "aws_iam_instance_profile" "exercise" {
  name = "Week2Exercise8InstanceProfile"
  path = local.role_path
  role = aws_iam_role.exercise.name
}

resource "aws_security_group" "exercise" {
  # checkov:skip=CKV2_AWS_5: The security group is attached to the disposable EC2 instance below.
  name_prefix = "week2-exercise8-"
  description = "No-ingress security group for the Week 2 EC2 workload-identity exercise."
  vpc_id      = data.aws_subnet.selected.vpc_id

  egress {
    description = "HTTPS to AWS public service endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS over UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS over TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name     = "Week2Exercise8NoIngress"
    Exercise = "8"
  }
}

resource "aws_instance" "exercise" {
  # checkov:skip=CKV_AWS_126: Detailed monitoring adds cost and is not required for this short-lived identity bootstrap test.
  # checkov:skip=CKV_AWS_8: This disposable lab fixture intentionally uses an unencrypted root volume temporarily; EBS default encryption is disabled and the KMS grant design is deferred.
  # checkov:skip=CKV_AWS_135: The small disposable root volume uses the AMI default throughput; no workload data is retained.
  # checkov:skip=CKV_AWS_318: The instance exists to emit controlled identity evidence through console output; detailed monitoring is unrelated.
  # checkov:skip=CKV_AWS_88: A public address provides temporary egress to public STS and S3 endpoints in a default subnet; the security group has no ingress and the instance is destroyed with the exercise.
  ami                         = local.effective_ami
  instance_type               = var.instance_type
  subnet_id                   = local.effective_subnet
  vpc_security_group_ids      = [aws_security_group.exercise.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.exercise.name
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    # Temporary lab choice: avoid the account KMS-grant path until the narrowly
    # scoped EC2/KMS design is implemented. EBS default encryption is disabled
    # in this account, so this disposable root volume remains unencrypted.
    encrypted   = false
    volume_type = "gp3"
  }

  user_data = <<-EOT
    #!/bin/bash
    set -u
    export AWS_DEFAULT_REGION=${var.aws_region}
    exec > >(tee /var/log/week2-exercise8.log) 2>&1
    echo "EXERCISE8_BEGIN"
    echo "IDENTITY"
    aws sts get-caller-identity
    echo "HAPPY_PATH"
    aws s3api get-object --bucket ${aws_s3_bucket.exercise.id} --key ${aws_s3_object.allowed.key} /tmp/exercise8-allowed.txt
    cat /tmp/exercise8-allowed.txt
    echo "UNHAPPY_PATH"
    if aws s3api get-object --bucket ${aws_s3_bucket.exercise.id} --key ${aws_s3_object.denied.key} /tmp/exercise8-denied.txt; then
      echo "UNEXPECTED_DENIED_OBJECT_READ_SUCCEEDED"
    else
      echo "EXPECTED_DENIED_OBJECT_READ_FAILED"
    fi
    rm -f /tmp/exercise8-allowed.txt /tmp/exercise8-denied.txt
    echo "EXERCISE8_END"
  EOT

  tags = {
    Name     = "Week2Exercise8Instance"
    Exercise = "8"
  }

  volume_tags = {
    Name     = "Week2Exercise8RootVolume"
    Exercise = "8"
  }

  lifecycle {
    precondition {
      condition     = local.effective_ami != ""
      error_message = "No Amazon Linux 2023 AMI was discovered; set ami_id explicitly."
    }

    precondition {
      condition     = local.effective_subnet != ""
      error_message = "No available subnet tagged Purpose=LabExercises and Network=Public was discovered; apply terraform/lab/foundation or set subnet_id explicitly."
    }
  }

  depends_on = [
    aws_s3_bucket_public_access_block.exercise,
    aws_s3_object.allowed,
    aws_s3_object.denied,
  ]
}

output "role_arn" {
  value = aws_iam_role.exercise.arn
}

output "instance_profile_arn" {
  value = aws_iam_instance_profile.exercise.arn
}

output "instance_id" {
  value = aws_instance.exercise.id
}

output "bucket_name" {
  value = aws_s3_bucket.exercise.id
}

output "allowed_object_key" {
  value = aws_s3_object.allowed.key
}

output "denied_object_key" {
  value = aws_s3_object.denied.key
}

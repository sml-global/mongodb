resource "aws_security_group" "efs" {
  name_prefix = "${var.name_prefix}-efs-"
  description = "Restricts NFS traffic to the EKS VPC."
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "this" {
  encrypted        = true
  throughput_mode  = var.throughput_mode
  performance_mode = "generalPurpose"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.name_prefix}-efs"
  }
}

resource "aws_efs_mount_target" "this" {
  count = length(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}
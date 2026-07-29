locals {
  enabled_addons = {
    for name, addon in var.addons : name => addon
    if addon.enabled
  }
}

resource "aws_eks_cluster" "this" {
  name     = "${var.name_prefix}-cluster"
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode = var.authentication_mode
  }

  vpc_config {
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    subnet_ids              = var.private_subnet_ids
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  encryption_config {
    provider {
      key_arn = var.cluster_kms_key_arn
    }
    resources = ["secrets"]
  }

  deletion_protection = var.deletion_protection
}

resource "aws_launch_template" "node" {
  name_prefix   = "${var.name_prefix}-node-"
  image_id      = null
  instance_type = var.node_instance_type

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  update_default_version = true
}

resource "aws_eks_node_group" "primary" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name_prefix}-primary"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.node_spot_enabled ? "SPOT" : "ON_DEMAND"
  instance_types = [var.node_instance_type]

  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  depends_on = [aws_eks_cluster.this]
}

resource "aws_eks_addon" "managed" {
  for_each = local.enabled_addons

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.addon_version
  resolve_conflicts_on_create = each.value.resolve_conflicts
  resolve_conflicts_on_update = each.value.resolve_conflicts
  service_account_role_arn    = each.value.service_account_role ? var.addon_role_arn : null
  configuration_values        = each.value.configuration_values

  depends_on = [aws_eks_node_group.primary]
}
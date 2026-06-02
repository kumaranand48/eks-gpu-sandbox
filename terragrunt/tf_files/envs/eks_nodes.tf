# Launch template carries ONLY the disk (block_device_mappings). No image_id /
# user_data — EKS injects the AMI + bootstrap based on the node group's ami_type.
resource "aws_launch_template" "node" {
  for_each = var.eks_node_groups
  name     = "${local.stack_name}-${each.key}"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = each.value.volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge({ Name = "${local.stack_name}-${each.key}" }, local.common_tags)
  }

  tags = local.common_tags
}

resource "aws_eks_node_group" "this" {
  for_each = var.eks_node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.stack_name}-${each.key}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [for s in aws_subnet.public : s.id]
  instance_types  = each.value.instance_types
  ami_type        = each.value.ami_type
  capacity_type   = each.value.capacity_type
  labels          = each.value.labels

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge({
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${local.stack_name}" = "owned"
  }, local.common_tags)

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_compute,
  ]

  # desired_size is managed out-of-band (make stop/start, cluster-autoscaler).
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# Tag each managed node group's ASG for cluster-autoscaler auto-discovery
# (node-group tags do NOT propagate to the underlying ASG).
resource "aws_autoscaling_group_tag" "ca_enabled" {
  for_each               = var.eks_node_groups
  autoscaling_group_name = aws_eks_node_group.this[each.key].resources[0].autoscaling_groups[0].name
  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "ca_owned" {
  for_each               = var.eks_node_groups
  autoscaling_group_name = aws_eks_node_group.this[each.key].resources[0].autoscaling_groups[0].name
  tag {
    key                 = "k8s.io/cluster-autoscaler/${local.stack_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

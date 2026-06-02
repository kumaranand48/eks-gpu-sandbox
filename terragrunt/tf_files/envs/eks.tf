resource "aws_eks_cluster" "main" {
  name     = local.stack_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.eks_kubernetes_version

  vpc_config {
    subnet_ids              = [for s in aws_subnet.public : s.id]
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.eks_master_public_access_cidrs
  }

  # API access entries (no aws-auth ConfigMap).
  access_config {
    authentication_mode = "API"
  }

  tags       = local.common_tags
  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# Cluster-creator admin (replaces enable_cluster_creator_admin_permissions).
resource "aws_eks_access_entry" "creator" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "creator_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.creator]
}

# ── Addons ──
# vpc-cni / kube-proxy install BEFORE node groups (CNI must be ready or nodes
# never go Ready); coredns / pod-identity install AFTER nodes exist.
resource "aws_eks_addon" "before_compute" {
  for_each = { for k, v in var.eks_addons : k => v if v.before_compute }

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.key
  addon_version               = each.value.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "after_compute" {
  for_each = { for k, v in var.eks_addons : k => v if !v.before_compute }

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.key
  addon_version               = each.value.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.this]
}

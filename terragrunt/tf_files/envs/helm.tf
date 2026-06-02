provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--region", var.aws_region, "--profile", var.aws_profile]
    }
  }
}

# Every helm_release depends on the cluster-admin access grant. The provider acts as
# the caller (the IAM principal running Terraform), who has NO cluster permissions under authentication_mode
# "API" without it. Critically this also fixes DESTROY ordering: Terraform tears the
# releases down BEFORE revoking admin, so `helm uninstall` keeps working on destroy.

# ── Node Feature Discovery — labels GPU nodes (pci-0302_10de.present) ──
resource "helm_release" "nfd" {
  name             = "nfd"
  namespace        = "nfd"
  repository       = "https://kubernetes-sigs.github.io/node-feature-discovery/charts"
  chart            = "node-feature-discovery"
  version          = var.gpu_stack.nfd_version
  create_namespace = true

  values = [file("${var.helm_charts_dir}/node-feature-discovery/values.yaml")]

  depends_on = [aws_eks_node_group.this, aws_eks_access_policy_association.creator_admin]
}

# ── NVIDIA device plugin + GFD — values override the chart's legacy affinity
#    to match modern NFD's pci-0302_10de label (see helm_charts values) ──
resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  namespace  = "kube-system"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = var.gpu_stack.device_plugin_version

  values = [file("${var.helm_charts_dir}/nvidia-device-plugin/values.yaml")]

  depends_on = [helm_release.nfd, aws_eks_access_policy_association.creator_admin]
}

# ── KEDA — pod-level autoscaler ──
resource "helm_release" "keda" {
  name             = "keda"
  namespace        = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.gpu_stack.keda_version
  create_namespace = true

  depends_on = [aws_eks_node_group.this, aws_eks_access_policy_association.creator_admin]
}

# ── Cluster Autoscaler — uses the EKS Pod Identity association from iam.tf ──
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.gpu_stack.cluster_autoscaler_version

  set {
    name  = "autoDiscovery.clusterName"
    value = local.stack_name
  }
  set {
    name  = "awsRegion"
    value = var.aws_region
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }
  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "5m"
  }
  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "5m"
  }
  set {
    name  = "extraArgs.skip-nodes-with-local-storage"
    value = "false"
  }

  depends_on = [
    aws_eks_pod_identity_association.cluster_autoscaler,
    aws_autoscaling_group_tag.ca_enabled,
    aws_autoscaling_group_tag.ca_owned,
    aws_eks_access_policy_association.creator_admin,
  ]
}

# ── vLLM test workload — vendored chart; wait=false (cold start > helm 300s) ──
resource "helm_release" "vllm_test" {
  count = var.vllm_enabled ? 1 : 0

  name      = "vllm-test"
  namespace = "default"
  chart     = "${var.helm_charts_dir}/vllm-test"
  wait      = false
  timeout   = 600

  depends_on = [helm_release.nvidia_device_plugin, aws_eks_access_policy_association.creator_admin]
}

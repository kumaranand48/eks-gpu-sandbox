include {
  path = find_in_parent_folders("common.hcl")
}

terraform {
  source = "${get_parent_terragrunt_dir()}//tf_files/envs/"
}

# ─────────────────────────────────────────────────────────────────────────────
# Pure data. ALL environment-specific config lives here; the TF root in
# tf_files/envs/ is generic and `for_each`-es over these maps. Add or change
# infra by editing DATA below — never the .tf files.
# ─────────────────────────────────────────────────────────────────────────────
inputs = {
  project_name = "infra" # stack_name = "${project_name}-${project_env}" = "infra-sandbox"
  project_env  = "sandbox"
  aws_profile  = "default"
  aws_region   = "us-west-2"

  # ── VPC (public-only, no NAT — cost-optimized throwaway) ──
  vpc_cidr_block        = "10.0.0.0/16"
  public_subnet_newbits = 8
  az_count              = 2

  # ── EKS ──
  eks_kubernetes_version         = "1.33"
  eks_master_public_access_cidrs = ["0.0.0.0/0"]

  # before_compute = true installs the addon before node groups (CNI must be
  # ready or nodes never go Ready). version omitted => AWS default for the cluster.
  eks_addons = {
    vpc-cni                = { before_compute = true }
    kube-proxy             = { before_compute = true }
    coredns                = {}
    eks-pod-identity-agent = {}
  }

  eks_node_groups = {
    system = {
      instance_types = ["t3.small"]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      volume_size    = 40
    }
    gpu = {
      instance_types = ["g6.xlarge"]
      ami_type       = "AL2023_x86_64_NVIDIA"
      min_size       = 0
      max_size       = 2
      desired_size   = 1
      volume_size    = 100
      labels = {
        workload = "inference"
        gpu      = "l4"
      }
      taints = {
        nvidia = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # ── GPU stack + KEDA + cluster-autoscaler (Helm) ──
  gpu_stack = {
    nfd_version                = "0.18.3"
    device_plugin_version      = "0.19.2"
    keda_version               = "2.19.0"
    cluster_autoscaler_version = "9.51.0"
  }

  # ── vLLM test workload (vendored chart in helm_charts/vllm-test) ──
  vllm_enabled = true
}

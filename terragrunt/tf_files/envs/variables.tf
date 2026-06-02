# ─────────────────────────────── Identity ───────────────────────────────
variable "aws_profile" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "project_name" {
  type = string
}

variable "project_env" {
  type = string
}

# ─────────────────────────────── VPC ───────────────────────────────
variable "vpc_cidr_block" {
  type = string
}

variable "public_subnet_newbits" {
  type = number
}

variable "az_count" {
  type    = number
  default = 2
}

# ─────────────────────────────── EKS ───────────────────────────────
variable "eks_kubernetes_version" {
  type = string
}

variable "eks_master_public_access_cidrs" {
  type = list(string)
}

variable "eks_addons" {
  type = map(object({
    before_compute = optional(bool, false)
    version        = optional(string) # null => AWS default for the cluster version
  }))
  default = {}
}

variable "eks_node_groups" {
  type = map(object({
    instance_types = list(string)
    ami_type       = string
    min_size       = number
    max_size       = number
    desired_size   = number
    volume_size    = optional(number, 20)
    capacity_type  = optional(string, "ON_DEMAND")
    labels         = optional(map(string), {})
    taints = optional(map(object({
      key    = string
      value  = string
      effect = string
    })), {})
  }))
  default = {}
}

# ─────────────────────────────── Helm stack ───────────────────────────────
variable "gpu_stack" {
  type = object({
    nfd_version                = string
    device_plugin_version      = string
    keda_version               = string
    cluster_autoscaler_version = string
  })
}

variable "vllm_enabled" {
  type    = bool
  default = true
}

# Injected by common.hcl
variable "helm_charts_dir" {
  type = string
}

# ─────────────────────────────── Derived ───────────────────────────────
locals {
  stack_name = "${var.project_name}-${var.project_env}"
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  common_tags = {
    project     = var.project_name
    env         = var.project_env
    provisioner = "terraform"
    Throwaway   = "true"
  }
}

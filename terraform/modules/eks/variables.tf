variable "project" {
  description = "Project name, used for resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.33" # 1.29 (the version in docs/technical-spec.md) has aged out of EKS support entirely; 1.33 is the oldest version still on free standard support as of 2026-07.
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS cluster and node group (public subnets, all-public design — see ADR-0001)"
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "Security group ID attached to the EKS control plane's cross-account ENIs (from the vpc module)"
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID attached to EKS worker nodes (from the vpc module)"
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for the managed node group"
  type        = string
  default     = "AL2023_ARM_64_STANDARD" # AL2_ARM_64 (the AL2 family) reached end of support and is rejected outright on K8s 1.33+ clusters; AL2023 is AWS's replacement.
}

variable "node_capacity_type" {
  description = "Capacity type for the managed node group"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Worker node root EBS volume size, in GB"
  type        = number
  default     = 20
}

variable "node_taints" {
  description = "Kubernetes taints to apply to the managed node group"
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  default = []
}

variable "cluster_log_types" {
  description = "EKS control plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "authentication_mode" {
  description = "EKS cluster authentication mode"
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "addon_versions" {
  description = "Explicit version override per add-on name (coredns, kube-proxy, vpc-cni, aws-ebs-csi-driver). Add-ons not listed here resolve to the EKS-recommended default version for the cluster's Kubernetes version — never \"most recent\"."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Additional tags to merge into every resource"
  type        = map(string)
  default     = {}
}

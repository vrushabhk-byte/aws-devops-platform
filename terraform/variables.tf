variable "aws_region" {
  description = "AWS region in which to deploy the platform."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short project identifier used in resource names."
  type        = string
  default     = "aws-devops-platform"
}

variable "environment" {
  description = "Environment label applied to resources."
  type        = string
  default     = "dev"
}

variable "cluster_version" {
  description = "Kubernetes version supported by Amazon EKS in the selected region."
  type        = string
  default     = "1.33"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR allowlist for the public EKS API endpoint. Set this to your trusted public IP /32."
  type        = list(string)
  default     = ["127.0.0.1/32"]
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum managed worker node count."
  type        = number
  default     = 1
}

variable "node_desired_size" {
  description = "Initial desired managed worker node count."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum managed worker node count."
  type        = number
  default     = 3
}

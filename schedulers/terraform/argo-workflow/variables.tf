variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "argoworkflows-eks"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
  default     = "us-east-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.27"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  default     = "10.1.0.0/16"
  type        = string
}

variable "public_subnets" {
  description = "Public Subnets CIDRs. 4094 IPs per Subnet"
  default     = ["10.1.192.0/20", "10.1.208.0/20", "10.1.224.0/20"]
  type        = list(string)
}

variable "private_subnets" {
  description = "Private Subnets CIDRs. 16382 IPs per Subnet"
  default     = ["10.1.0.0/18", "10.1.64.0/18", "10.1.128.0/18"]
  type        = list(string)
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}

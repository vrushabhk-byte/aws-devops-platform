data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

locals {
  name = var.project_name
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  interface_endpoint_services = toset([
    "ecr.api",
    "ecr.dkr",
    "ec2",
    "sts"
  ])
}

# ------------------------------------------------------------
# VPC
# ------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = "10.20.0.0/16"

  azs             = local.azs
  private_subnets = ["10.20.1.0/24", "10.20.2.0/24"]
  public_subnets  = ["10.20.101.0/24", "10.20.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ------------------------------------------------------------
# EKS
# ------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false

  enable_cluster_creator_admin_permissions = true

  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  cloudwatch_log_group_retention_in_days = 14

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Do not create the module's unrestricted recommended egress rules.
  node_security_group_enable_recommended_rules = false

  eks_managed_node_groups = {
    default = {
      name           = "${local.name}-workers"
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      labels = {
        workload = "general"
      }
    }
  }

  tags = {
    Project = var.project_name
  }

  depends_on = [module.vpc]
}

# ------------------------------------------------------------
# Interface VPC endpoint security group
# ------------------------------------------------------------

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.name}-vpce-"
  description = "Security group for private AWS service endpoints"
  vpc_id      = module.vpc.vpc_id

  # Rules are managed separately below.
  ingress = []
  egress  = []

  tags = {
    Name    = "${local.name}-vpce"
    Project = var.project_name
  }
}

# Permit HTTPS from EKS worker nodes to the interface endpoints.
resource "aws_vpc_security_group_ingress_rule" "endpoint_https_from_nodes" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  referenced_security_group_id = module.eks.node_security_group_id

  description = "Allow HTTPS from EKS worker nodes"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
}

# Permit worker nodes to reach the interface endpoints over HTTPS.
resource "aws_vpc_security_group_egress_rule" "nodes_to_interface_endpoints" {
  security_group_id            = module.eks.node_security_group_id
  referenced_security_group_id = aws_security_group.vpc_endpoints.id

  description = "Allow HTTPS to approved AWS interface endpoints"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
}

# Permit worker nodes to reach the private EKS control plane over HTTPS.
resource "aws_vpc_security_group_egress_rule" "nodes_to_eks_control_plane" {
  security_group_id            = module.eks.node_security_group_id
  referenced_security_group_id = module.eks.cluster_primary_security_group_id

  description = "Allow HTTPS to the EKS cluster security group"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
}

# Permit DNS queries to the VPC resolver range.
resource "aws_vpc_security_group_egress_rule" "nodes_dns_udp" {
  security_group_id = module.eks.node_security_group_id

  description = "Allow DNS queries over UDP within the VPC"
  ip_protocol = "udp"
  from_port   = 53
  to_port     = 53
  cidr_ipv4   = "10.20.0.0/16"
}

resource "aws_vpc_security_group_egress_rule" "nodes_dns_tcp" {
  security_group_id = module.eks.node_security_group_id

  description = "Allow DNS queries over TCP within the VPC"
  ip_protocol = "tcp"
  from_port   = 53
  to_port     = 53
  cidr_ipv4   = "10.20.0.0/16"
}

# Permit HTTPS to the AWS-managed S3 prefix list.
# ECR uses S3 for image layers.
resource "aws_vpc_security_group_egress_rule" "nodes_to_s3" {
  security_group_id = module.eks.node_security_group_id

  description    = "Allow HTTPS to AWS S3 managed prefix list"
  ip_protocol    = "tcp"
  from_port      = 443
  to_port        = 443
  prefix_list_id = data.aws_prefix_list.s3.id
}

# ------------------------------------------------------------
# Interface VPC endpoints
# ------------------------------------------------------------

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = module.vpc.private_subnets

  security_group_ids = [
    aws_security_group.vpc_endpoints.id
  ]

  tags = {
    Name    = "${local.name}-${replace(each.value, ".", "-")}"
    Project = var.project_name
  }
}

# ------------------------------------------------------------
# S3 gateway endpoint
# ------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = module.vpc.private_route_table_ids

  tags = {
    Name    = "${local.name}-s3"
    Project = var.project_name
  }
}

# ------------------------------------------------------------
# ECR repository
# ------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = var.project_name
    Project = var.project_name
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the most recent 20 images"

        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}

output "aws_region" {
  description = "AWS region for this deployment."
  value       = var.aws_region
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for the application image."
  value       = aws_ecr_repository.app.repository_url
}

output "vpc_id" {
  description = "VPC ID created by this project."
  value       = module.vpc.vpc_id
}

output "kubeconfig_command" {
  description = "Run this command to configure kubectl."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

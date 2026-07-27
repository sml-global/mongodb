output "vpc_id" {
  description = "VPC ID for the EKS platform."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block for downstream network policy constraints."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs for EKS worker and stateful data plane resources."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "public_subnet_ids" {
  description = "Public subnet IDs for internet-facing load balancers when needed."
  value       = [for subnet in aws_subnet.public : subnet.id]
}
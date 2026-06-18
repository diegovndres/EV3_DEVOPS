terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ==========================================
# ROL IAM: LabRole (AWS Academy)
# ==========================================
data "aws_iam_role" "labrole" {
  name = "LabRole"
}

# ==========================================
# VPC + SUBREDES + INTERNET GATEWAY
# ==========================================
resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "innovatech-vpc"
  }
}

resource "aws_subnet" "eks_subnet_1" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "innovatech-subnet-1"
    "kubernetes.io/cluster/innovatech-cluster"  = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_subnet" "eks_subnet_2" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.20.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "innovatech-subnet-2"
    "kubernetes.io/cluster/innovatech-cluster"  = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags = {
    Name = "innovatech-igw"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "innovatech-route-table"
  }
}

resource "aws_route_table_association" "rta_1" {
  subnet_id      = aws_subnet.eks_subnet_1.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "rta_2" {
  subnet_id      = aws_subnet.eks_subnet_2.id
  route_table_id = aws_route_table.rt.id
}

# ==========================================
# SECURITY GROUPS
# ==========================================

# SG para los nodos EKS (permite tráfico entre nodos y desde ALB)
resource "aws_security_group" "eks_nodes_sg" {
  name        = "innovatech-eks-nodes-sg"
  description = "Security group para nodos EKS"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    description = "Trafico interno entre nodos"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "HTTP desde internet (LoadBalancer)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort rango para servicios K8s"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Backend Ventas (ClusterIP interno)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Backend Despachos (ClusterIP interno)"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "MySQL (solo trafico interno del cluster)"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Salida a internet (para ECR, CloudWatch)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "innovatech-eks-nodes-sg"
  }
}

# ==========================================
# EKS: Cluster + Node Group
# ==========================================
resource "aws_eks_cluster" "eks" {
  name     = "innovatech-cluster"
  role_arn = data.aws_iam_role.labrole.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.eks_subnet_1.id,
      aws_subnet.eks_subnet_2.id
    ]
    security_group_ids      = [aws_security_group.eks_nodes_sg.id]
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # Logging del control plane hacia CloudWatch Logs.
  # EKS crea automaticamente el log group /aws/eks/innovatech-cluster/cluster
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name = "innovatech-cluster"
  }
}

resource "aws_launch_template" "workers_lt" {
  name_prefix = "innovatech-workers-"

  # Fija el hop-limit del IMDS en 2. Por defecto EKS lo crea en 1, lo que
  # bloquea a los pods (ej. Fluent Bit) para obtener credenciales de
  # LabRole via el servicio de metadata de EC2 (169.254.169.254).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "innovatech-workers"
    }
  }
}

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "workers"
  node_role_arn   = data.aws_iam_role.labrole.arn

  subnet_ids = [
    aws_subnet.eks_subnet_1.id,
    aws_subnet.eks_subnet_2.id
  ]

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.workers_lt.id
    version = "$Latest"
  }

  tags = {
    Name = "innovatech-workers"
  }
}

# ==========================================
# ECR: Repositorios de imágenes
# ==========================================
resource "aws_ecr_repository" "backend_ventas" {
  name = "innovatech-backend-ventas"
  image_scanning_configuration {
    scan_on_push = true
  }
  force_delete = true
  tags = {
    Name = "innovatech-backend-ventas"
  }
}

resource "aws_ecr_repository" "backend_despachos" {
  name = "innovatech-backend-despachos"
  image_scanning_configuration {
    scan_on_push = true
  }
  force_delete = true
  tags = {
    Name = "innovatech-backend-despachos"
  }
}

resource "aws_ecr_repository" "frontend" {
  name = "innovatech-frontend"
  image_scanning_configuration {
    scan_on_push = true
  }
  force_delete = true
  tags = {
    Name = "innovatech-frontend"
  }
}

# ==========================================
# OUTPUTS
# ==========================================
output "cluster_name" {
  value = aws_eks_cluster.eks.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "vpc_id" {
  value = aws_vpc.eks_vpc.id
}

output "security_group_nodes" {
  value = aws_security_group.eks_nodes_sg.id
}

output "backend_ventas_ecr_url" {
  value = aws_ecr_repository.backend_ventas.repository_url
}

output "backend_despachos_ecr_url" {
  value = aws_ecr_repository.backend_despachos.repository_url
}

output "frontend_ecr_url" {
  value = aws_ecr_repository.frontend.repository_url
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

##############################
# VPC
##############################

resource "aws_vpc" "eks_vpc" {
  cidr_block           = "12.21.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "training-eks-vpc"
  }
}

##############################
# Internet Gateway
##############################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "training-eks-igw"
  }
}

##############################
# Public Subnet 1
##############################

resource "aws_subnet" "public_subnet1" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "12.21.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "public-subnet-1"
    "kubernetes.io/role/elb" = "1"
  }
}

##############################
# Public Subnet 2
##############################

resource "aws_subnet" "public_subnet2" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "12.21.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "public-subnet-2"
    "kubernetes.io/role/elb" = "1"
  }
}

##############################
# Route Table
##############################

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "subnet1" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "subnet2" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.public_rt.id
}

##############################
# IAM Role - EKS Cluster
##############################

resource "aws_iam_role" "eks_cluster_role" {
  name = "training-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "eks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

##############################
# IAM Role - Worker Nodes
##############################

resource "aws_iam_role" "node_role" {
  name = "training-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

##############################
# EKS Cluster
##############################

resource "aws_eks_cluster" "eks_cluster" {
  name     = "training-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.public_subnet1.id,
      aws_subnet.public_subnet2.id
    ]

    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]

  tags = {
    Name = "training-eks-cluster"
  }
}

##############################
# Managed Node Group
##############################

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "public-workers"
  node_role_arn   = aws_iam_role.node_role.arn

  subnet_ids = [
    aws_subnet.public_subnet1.id,
    aws_subnet.public_subnet2.id
  ]

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  depends_on = [
    aws_iam_role_policy_attachment.worker_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_policy,
    aws_eks_cluster.eks_cluster
  ]

  tags = {
    Name = "public-workers"
  }
}

##############################
# Outputs
##############################

output "cluster_name" {
  value = aws_eks_cluster.eks_cluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "vpc_id" {
  value = aws_vpc.eks_vpc.id
}

output "subnets" {
  value = [
    aws_subnet.public_subnet1.id,
    aws_subnet.public_subnet2.id
  ]
}

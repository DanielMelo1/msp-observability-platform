# ─────────────────────────────────────────────────────────────────────────────
# NETWORKING MODULE — VPC, Subnets, Gateways, Flow Logs
# ─────────────────────────────────────────────────────────────────────────────
# Creates the network foundation for the EKS cluster.
#
# Security controls implemented:
#   - VPC Flow Logs enabled (CloudWatch) for network audit trail
#   - Default security group with all traffic blocked
#   - Public subnets without automatic public IP assignment
#   - Private subnets for EKS worker nodes
#   - NAT Gateways for private subnet internet access
# ─────────────────────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────
# VPC
# ───────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.tags,
    {
      Name = var.vpc_name
    }
  )
}

# ───────────────────────────────────────────────────────────
# VPC FLOW LOGS
# ───────────────────────────────────────────────────────────
# Records all network traffic in the VPC to CloudWatch.
# Checkov CKV2_AWS_11: required for security incident investigation.
# Without flow logs it is impossible to trace suspicious traffic.
# ───────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/flow-logs/${var.vpc_name}"
  retention_in_days = 30

  tags = merge(
    var.tags,
    {
      Name    = "${var.vpc_name}-flow-logs"
      Purpose = "VPC network traffic audit"
    }
  )
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.vpc_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.vpc_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-flow-log"
    }
  )
}

# ───────────────────────────────────────────────────────────
# DEFAULT SECURITY GROUP — RESTRICT ALL TRAFFIC
# ───────────────────────────────────────────────────────────
# The default security group must have all traffic blocked.
# Checkov CKV2_AWS_12: prevents accidental exposure if a
# resource is launched without an explicit security group.
# ───────────────────────────────────────────────────────────
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  # No ingress or egress rules — all traffic blocked by default
  # This is intentional. Resources must use explicit security groups.

  tags = merge(
    var.tags,
    {
      Name    = "${var.vpc_name}-default-sg-restricted"
      Purpose = "Default SG with all traffic blocked — do not use"
    }
  )
}

# ───────────────────────────────────────────────────────────
# INTERNET GATEWAY
# ───────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-igw"
    }
  )
}

# ───────────────────────────────────────────────────────────
# PUBLIC SUBNETS
# ───────────────────────────────────────────────────────────
# Host NAT Gateways and Load Balancers only.
# map_public_ip_on_launch = false — resources do not get
# public IPs automatically. Only IGW-routed resources
# that explicitly need it should have public IPs.
# Checkov CKV_AWS_130: prevents accidental public exposure.
# ───────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  # map_public_ip_on_launch intentionally set to false
  # EKS load balancers use Elastic IPs — not instance public IPs
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.vpc_name}-public-${count.index + 1}"
      "kubernetes.io/role/elb"                    = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }
  )
}

# ───────────────────────────────────────────────────────────
# PRIVATE SUBNETS
# ───────────────────────────────────────────────────────────
# Host EKS worker nodes and application pods.
# No public IP — all outbound through NAT Gateway.
# ───────────────────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.vpc_name}-private-${count.index + 1}"
      "kubernetes.io/role/internal-elb"           = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }
  )
}

# ───────────────────────────────────────────────────────────
# ELASTIC IPs FOR NAT GATEWAYS
# ───────────────────────────────────────────────────────────
resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-nat-eip-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# ───────────────────────────────────────────────────────────
# NAT GATEWAYS
# ───────────────────────────────────────────────────────────
# One per AZ for high availability.
# Provides outbound internet for private subnets
# (worker nodes need to pull container images from ECR).
# ───────────────────────────────────────────────────────────
resource "aws_nat_gateway" "main" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-nat-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# ───────────────────────────────────────────────────────────
# ROUTE TABLES
# ───────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-public-rt"
    }
  )
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-private-rt-${count.index + 1}"
    }
  )
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

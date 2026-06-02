# Public-only VPC (no NAT) — cost-optimized sandbox. Subnets sized by
# cidrsubnet(cidr, newbits, idx): /16 + 8 newbits => /24 per AZ.

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge({ Name = local.stack_name }, local.common_tags)
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge({ Name = local.stack_name }, local.common_tags)
}

resource "aws_subnet" "public" {
  for_each = { for idx, az in local.azs : az => idx }

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr_block, var.public_subnet_newbits, each.value)
  map_public_ip_on_launch = true

  tags = merge({
    Name                                        = "${local.stack_name}-public-${each.key}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${local.stack_name}" = "shared"
  }, local.common_tags)
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge({ Name = "${local.stack_name}-public" }, local.common_tags)
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

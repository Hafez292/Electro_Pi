resource "aws_vpc" "main" {
  cidr_block       = var.cidr_vpc
  enable_dns_hostnames = var.enable_dns_hostnames
  tags = {
    Name = var.tag_vpc
  }
}
#Subnets
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  for_each = var.cidr_Pub_Subnets
  cidr_block = each.value
  availability_zone = element(var.azs, index(keys(var.cidr_Pub_Subnets), each.key))
  tags = {
    Name = "${each.key}"
  }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  for_each = var.cidr_Pri_Subnets
  cidr_block = each.value
  availability_zone = element(var.azs, index(keys(var.cidr_Pri_Subnets), each.key))
  tags = {
    Name = "${each.key}"
  }
  
}

# IGW
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "IGW"
  }
}


#Public_Router
resource "aws_route_table" "public_router" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public_Router"
  }
}


# Public & Private-Assoation
resource "aws_route_table_association" "public_Assoation" {
  for_each = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_router.id
  depends_on = [aws_route_table.public_router]
}

############### This Section To Enable NAT & Attach With Private Subnets ##############

 #EL_IP
resource "aws_eip" "eip" {
  domain = "vpc"
}
# NAT-GW

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = values(aws_subnet.public)[0].id
  tags = {
    Name = "NAT"
  }
}

#Private_Router
resource "aws_route_table" "private_router" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "Private_Router"
  }
}

resource "aws_route_table_association" "private_Assoation" {
  for_each = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_router.id
  depends_on = [aws_route_table.private_router]
}
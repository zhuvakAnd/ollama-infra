resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "3tier-vpc"
  }
}

data "aws_availability_zones" "azs" {}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.azs.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public"
  }
}
resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.azs.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public1"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.azs.names[0]

  tags = {
    Name = "Private"
  }
}
resource "aws_subnet" "private1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.azs.names[1]

  tags = {
    Name = "Private1"
  }
}

resource "aws_subnet" "data" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = data.aws_availability_zones.azs.names[0]

  tags = {
    Name = "Data"
  }
}
resource "aws_subnet" "data1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = data.aws_availability_zones.azs.names[1]

  tags = {
    Name = "Data1"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Main"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_eip" "nat1" {
  domain = "vpc"
}

resource "aws_nat_gateway" "public_nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "Public NAT"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "public_nat1" {
  allocation_id = aws_eip.nat1.id
  subnet_id     = aws_subnet.public1.id

  tags = {
    Name = "Public NAT"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "app1" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "app_nat" {
  route_table_id         = aws_route_table.app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.public_nat.id
}

resource "aws_route" "app_nat1" {
  route_table_id         = aws_route_table.app1.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.public_nat1.id
}

resource "aws_route_table_association" "app1" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.app.id
}

resource "aws_route_table_association" "app2" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.app1.id
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "data1" {
  subnet_id      = aws_subnet.data.id
  route_table_id = aws_route_table.data.id
}

resource "aws_route_table_association" "data2" {
  subnet_id      = aws_subnet.data1.id
  route_table_id = aws_route_table.data.id
}

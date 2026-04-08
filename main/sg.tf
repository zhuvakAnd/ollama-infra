resource "aws_security_group" "app_sg" {
  name        = "SG-Application-Tier"
  description = "App tier SG"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "SG-Application-Tier"
  }
}
resource "aws_security_group" "db_sg" {
  name        = "SG-Data-Tier"
  description = "DB tier SG"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "SG-Data-Tier"
  }
}

resource "aws_security_group_rule" "app_to_db" {
  type      = "egress"
  from_port = 5432
  to_port   = 5432
  protocol  = "tcp"

  security_group_id        = aws_security_group.app_sg.id
  source_security_group_id = aws_security_group.db_sg.id
}

resource "aws_security_group_rule" "db_from_app" {
  type      = "ingress"
  from_port = 5432
  to_port   = 5432
  protocol  = "tcp"

  security_group_id        = aws_security_group.db_sg.id
  source_security_group_id = aws_security_group.app_sg.id
}

resource "aws_security_group_rule" "app_to_https" {
  type      = "egress"
  from_port = 443
  to_port   = 443
  protocol  = "tcp"

  security_group_id = aws_security_group.app_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_to_app" {
  type      = "egress"
  from_port = 8080
  to_port   = 8080
  protocol  = "tcp"

  security_group_id        = aws_security_group.alb_sg.id
  source_security_group_id = aws_security_group.app_sg.id
}

resource "aws_security_group_rule" "alb_from_internet" {
  type      = "ingress"
  from_port = 80
  to_port   = 80
  protocol  = "tcp"

  security_group_id = aws_security_group.alb_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "app_from_alb" {
  type      = "ingress"
  from_port = 8080
  to_port   = 8080
  protocol  = "tcp"

  security_group_id        = aws_security_group.app_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
}

resource "aws_security_group" "alb_sg" {
  name        = "SG-ALB"
  description = "ALB SG"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "SG-ALB"
  }
}

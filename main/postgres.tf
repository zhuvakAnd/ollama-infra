resource "aws_db_instance" "postgres" {
  identifier        = "postgres-db"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  username = var.db_username
  password = jsondecode(aws_secretsmanager_secret_version.db_password_value.secret_string)["password"]

  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  multi_az            = true
  publicly_accessible = false
  skip_final_snapshot = true

  tags = {
    Name = "Postgres-RDS"
  }

  depends_on = [
    aws_db_subnet_group.db_subnet_group,
    aws_security_group.db_sg,
    aws_secretsmanager_secret.db_password,
    aws_secretsmanager_secret_version.db_password_value
  ]
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_password" {
  name        = "prod/database/password6"
  description = "RDS PostgreSQL master password"
  tags = {
    Environment = "prod"
  }
}

resource "aws_secretsmanager_secret_version" "db_password_value" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    password = random_password.db_password.result
  })

  depends_on = [
    aws_secretsmanager_secret.db_password
  ]
}

resource "aws_secretsmanager_secret" "open_webui_database_url" {
  name        = "prod/open-webui/database-url1"
  description = "Open WebUI DATABASE_URL (plain string for ECS secret injection)"

  tags = {
    Environment = "prod"
  }
}

resource "aws_secretsmanager_secret_version" "open_webui_database_url" {
  secret_id     = aws_secretsmanager_secret.open_webui_database_url.id
  secret_string = "postgresql://${urlencode(var.db_username)}:${urlencode(random_password.db_password.result)}@${aws_db_instance.postgres.address}:5432/postgres"

  depends_on = [
    aws_secretsmanager_secret.open_webui_database_url,
    aws_db_instance.postgres
  ]
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name = "db-subnet-group"
  subnet_ids = [
    aws_subnet.data.id,
    aws_subnet.data1.id
  ]

  tags = {
    Name = "DB-Subnet-Group"
  }
}

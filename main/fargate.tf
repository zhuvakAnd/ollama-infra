resource "random_password" "webui_secret_key" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "webui" {
  name        = "prod/open-webui/webui-secret-key1"
  description = "Open WebUI WEBUI_SECRET_KEY (JSON key: key)"

  tags = {
    Environment = "prod"
  }
}

resource "aws_secretsmanager_secret_version" "webui" {
  secret_id = aws_secretsmanager_secret.webui.id
  secret_string = jsonencode({
    key = random_password.webui_secret_key.result
  })

  depends_on = [aws_secretsmanager_secret.webui]
}

resource "aws_ecs_cluster" "ollama_cluster" {
  name = "ollama-fargate-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "ollama-fargate-cluster"
  }
}

resource "aws_ecs_task_definition" "ollama_webui" {
  family                   = "ollama-webui-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "4096"
  memory = "8192"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([

    # --- Ollama container ---
    {
      name  = "ollama"
      image = "542776677488.dkr.ecr.us-east-1.amazonaws.com/ollama-app:v2"

      essential = true

      portMappings = [
        {
          containerPort = 11434
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/ollama"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ollama"
        }
      }

      # healthCheck = {
      #   command     = ["CMD-SHELL", "curl -f http://localhost:11434/api/tags || exit 1"]
      #   interval    = 30
      #   timeout     = 5
      #   retries     = 3
      #   startPeriod = 60
      # }
    },

    # --- Open WebUI container ---
    {
      name  = "open-webui"
      image = "ghcr.io/open-webui/open-webui:main"

      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "OLLAMA_BASE_URL"
          value = "http://127.0.0.1:11434"
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.open_webui_database_url.arn
        },
        {
          name      = "WEBUI_SECRET_KEY"
          valueFrom = "${aws_secretsmanager_secret.webui.arn}:key::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/open-webui"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "webui"
        }
      }

      # healthCheck = {
      #   command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      #   interval    = 30
      #   timeout     = 5
      #   retries     = 3
      #   startPeriod = 60
      # }

      # dependsOn = [
      #   {
      #     containerName = "ollama"
      #     condition     = "HEALTHY"
      #   }
      # ]
    }

  ])
}


resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "secrets_access" {
  name = "ecs-secrets-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "${aws_secretsmanager_secret.open_webui_database_url.arn}*",
          "${aws_secretsmanager_secret.webui.arn}*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_secrets" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "app_policy" {
  name = "ecs-app-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "${aws_secretsmanager_secret.open_webui_database_url.arn}*",
          "${aws_secretsmanager_secret.webui.arn}*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_attach" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.app_policy.arn
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/open-webui"
  retention_in_days = 7
}
resource "aws_cloudwatch_log_group" "ecs-ollama" {
  name              = "/ecs/ollama"
  retention_in_days = 7
}
resource "aws_lb_target_group" "webui_tg" {
  name        = "webui-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/"
    port                = "8080"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "webui_tg_green" {
  name        = "webui-tg-green"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/"
    port                = "8080"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb" "app_alb" {
  name               = "ollama-alb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.public.id, aws_subnet.public1.id]
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webui_tg.arn
  }
}

resource "aws_ecs_service" "ollama_service" {
  name            = "ollama-webui-service"
  cluster         = aws_ecs_cluster.ollama_cluster.id
  task_definition = aws_ecs_task_definition.ollama_webui.arn
  desired_count   = 2

  launch_type = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = [aws_subnet.private.id, aws_subnet.private1.id]
    security_groups  = [aws_security_group.app_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.webui_tg.arn
    container_name   = "open-webui"
    container_port   = 8080
  }

  depends_on = [
    aws_lb_listener.http
  ]

  # CodeDeploy manages task_definition, load_balancer, and desired_count
  # after the first deployment — ignore Terraform drift on these attributes.
  lifecycle {
    ignore_changes = [
      task_definition,
      load_balancer,
      desired_count
    ]
  }
}

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

  cpu    = "2048"
  memory = "8192"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([

    # --- Ollama container ---
    {
      name  = "ollama"
      image = "058264468006.dkr.ecr.us-east-1.amazonaws.com/ollama-app:latest"

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

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:11434 || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
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
          name  = "DB_HOST"
          value = aws_db_instance.postgres.address
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = var.db_username
        }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "arn:aws:secretsmanager:us-east-1:058264468006:secret:prod/database/password2-IluZKM"
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

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }

      dependsOn = [
        {
          containerName = "ollama"
          condition     = "START"
        }
      ]
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
        Resource = "arn:aws:secretsmanager:us-east-1:058264468006:secret:prod/database/password2*"
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
        Resource = "arn:aws:secretsmanager:us-east-1:058264468006:secret:prod/database/password2*"
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

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [
    aws_lb_listener.http
  ]
}

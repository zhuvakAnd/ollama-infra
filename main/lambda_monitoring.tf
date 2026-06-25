# ─── Health Monitoring Lambda Layer (psycopg2 / Python 3.13) ─────────────────

resource "terraform_data" "psycopg2_layer_build" {
  input = filemd5("${path.module}/lambda/layer/requirements.txt")

  provisioner "local-exec" {
    command     = "${path.module}/lambda/layer/build.py"
    interpreter = ["python"]
  }
}

resource "aws_lambda_layer_version" "psycopg2" {
  layer_name          = "psycopg2-python313"
  compatible_runtimes = ["python3.13"]
  filename            = "${path.module}/lambda/layer/psycopg2-layer.zip"
  source_code_hash    = filebase64sha256("${path.module}/lambda/layer/psycopg2-layer.zip")

  depends_on = [terraform_data.psycopg2_layer_build]
}

# ─── Health Monitoring Lambda Function ───────────────────────────────────────

data "archive_file" "health_monitor_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/health_monitor/handler.py"
  output_path = "${path.module}/lambda/health_monitor/lambda.zip"
}

resource "aws_cloudwatch_log_group" "health_monitor" {
  name              = "/aws/lambda/health-monitor"
  retention_in_days = 14

  tags = {
    Name        = "health-monitor-lambda"
    Environment = "prod"
  }
}

resource "aws_iam_role" "health_monitor_lambda" {
  name = "health-monitor-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "health-monitor-lambda-role"
    Environment = "prod"
  }
}

resource "aws_iam_role_policy_attachment" "health_monitor_lambda_basic" {
  role       = aws_iam_role.health_monitor_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "health_monitor_lambda_vpc" {
  role       = aws_iam_role.health_monitor_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "health_monitor_lambda" {
  name = "health-monitor-lambda-policy"
  role = aws_iam_role.health_monitor_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "${aws_secretsmanager_secret.db_password.arn}*"
        ]
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "health_monitor" {
  function_name = "health-monitor"
  description   = "Checks ALB health, queries RDS statistics, and publishes CloudWatch metrics"
  role          = aws_iam_role.health_monitor_lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.13"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.health_monitor_lambda.output_path
  source_code_hash = data.archive_file.health_monitor_lambda.output_base64sha256

  layers = [aws_lambda_layer_version.psycopg2.arn]

  vpc_config {
    subnet_ids         = [aws_subnet.private.id, aws_subnet.private1.id]
    security_group_ids = [aws_security_group.lambda_monitor_sg.id]
  }

  environment {
    variables = {
      DB_HOST        = aws_db_instance.postgres.address
      DB_PORT        = "5432"
      DB_NAME        = "postgres"
      DB_USER        = var.db_username
      DB_SECRET_ARN  = aws_secretsmanager_secret.db_password.arn
      ALB_ENDPOINT   = "http://${aws_lb.app_alb.dns_name}"
      SNS_TOPIC_ARN  = aws_sns_topic.health_alerts.arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.health_monitor,
    aws_iam_role_policy_attachment.health_monitor_lambda_basic,
    aws_iam_role_policy_attachment.health_monitor_lambda_vpc,
    aws_iam_role_policy.health_monitor_lambda,
    aws_security_group_rule.lambda_monitor_egress_https,
    aws_security_group_rule.lambda_monitor_egress_db,
    aws_security_group_rule.lambda_monitor_egress_alb,
    aws_security_group_rule.db_from_lambda_monitor,
    aws_security_group_rule.alb_from_lambda_monitor,
  ]

  tags = {
    Name        = "health-monitor"
    Environment = "prod"
  }
}

# ─── EventBridge Scheduled Rule (every 15 minutes) ─────────────────────────

resource "aws_cloudwatch_event_rule" "health_monitor_schedule" {
  name                = "health-monitor-schedule"
  description         = "Trigger health monitoring Lambda every 15 minutes"
  schedule_expression = "rate(15 minutes)"

  tags = {
    Name        = "health-monitor-schedule"
    Environment = "prod"
  }
}

resource "aws_cloudwatch_event_target" "health_monitor_lambda" {
  rule      = aws_cloudwatch_event_rule.health_monitor_schedule.name
  target_id = "HealthMonitorLambda"
  arn       = aws_lambda_function.health_monitor.arn
}

resource "aws_lambda_permission" "health_monitor_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_monitor_schedule.arn
}

# ─── SNS Topic for Health Alerts ─────────────────────────────────────────────

resource "aws_sns_topic" "health_alerts" {
  name = "health-monitoring-alerts"

  tags = {
    Name        = "health-monitoring-alerts"
    Environment = "prod"
  }
}

resource "aws_sns_topic_subscription" "health_alerts_email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.health_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_policy" "health_alerts" {
  arn = aws_sns_topic.health_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.health_alerts.arn
      }
    ]
  })
}

# ─── CloudWatch Alarms ───────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "application_unhealthy" {
  alarm_name          = "health-monitor-application-unhealthy"
  alarm_description   = "ALB endpoint did not return HTTP 200 for 3 consecutive checks (45 minutes)"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApplicationHealthy"
  namespace           = "Ollama/HealthMonitoring"
  period              = 900
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.health_alerts.arn]
  ok_actions    = [aws_sns_topic.health_alerts.arn]

  tags = {
    Name        = "application-unhealthy"
    Environment = "prod"
  }
}

resource "aws_cloudwatch_metric_alarm" "database_connections_high" {
  alarm_name          = "health-monitor-database-connections-high"
  alarm_description   = "RDS connection count exceeded ${var.db_connections_threshold}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "Ollama/HealthMonitoring"
  period              = 900
  statistic           = "Maximum"
  threshold           = var.db_connections_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.health_alerts.arn]
  ok_actions    = [aws_sns_topic.health_alerts.arn]

  tags = {
    Name        = "database-connections-high"
    Environment = "prod"
  }
}

resource "aws_cloudwatch_metric_alarm" "database_size_high" {
  alarm_name          = "health-monitor-database-size-high"
  alarm_description   = "RDS database size exceeded ${var.db_size_threshold_gb} GB"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseSizeBytes"
  namespace           = "Ollama/HealthMonitoring"
  period              = 900
  statistic           = "Maximum"
  threshold           = var.db_size_threshold_gb * 1024 * 1024 * 1024
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.health_alerts.arn]
  ok_actions    = [aws_sns_topic.health_alerts.arn]

  tags = {
    Name        = "database-size-high"
    Environment = "prod"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_unhealthy_targets" {
  alarm_name          = "health-monitor-ecs-unhealthy-targets"
  alarm_description   = "ECS service has unhealthy targets behind the ALB"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 900
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.webui_tg.arn_suffix
  }

  alarm_actions = [aws_sns_topic.health_alerts.arn]
  ok_actions    = [aws_sns_topic.health_alerts.arn]

  tags = {
    Name        = "ecs-unhealthy-targets"
    Environment = "prod"
  }
}

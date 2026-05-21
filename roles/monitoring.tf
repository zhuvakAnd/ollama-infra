# ─── SNS Topic for Pipeline Alerts ───────────────────────────────────────────

resource "aws_sns_topic" "pipeline_alerts" {
  name = "terraform-pipeline-alerts"

  tags = {
    Name        = "terraform-pipeline-alerts"
    Environment = "prod"
  }
}

resource "aws_sns_topic_subscription" "pipeline_alerts_email" {
  count = var.approval_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.approval_email
}

# ─── EventBridge – Pipeline State Change Events ───────────────────────────────

# Allow EventBridge to publish to the alerts SNS topic
resource "aws_sns_topic_policy" "pipeline_alerts" {
  arn = aws_sns_topic.pipeline_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.pipeline_alerts.arn
      }
    ]
  })
}

# Notify on pipeline failures
resource "aws_cloudwatch_event_rule" "pipeline_failed" {
  name        = "terraform-pipeline-failed"
  description = "Fires when the terraform-infra-pipeline execution fails"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      pipeline = [aws_codepipeline.terraform_pipeline.name]
      state    = ["FAILED"]
    }
  })

  tags = {
    Name        = "terraform-pipeline-failed"
    Environment = "prod"
  }
}

resource "aws_cloudwatch_event_target" "pipeline_failed_sns" {
  rule      = aws_cloudwatch_event_rule.pipeline_failed.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.pipeline_alerts.arn

  input_transformer {
    input_paths = {
      pipeline   = "$.detail.pipeline"
      state      = "$.detail.state"
      exec_id    = "$.detail.execution-id"
      account    = "$.account"
      region     = "$.region"
    }

    input_template = "\"Pipeline <pipeline> entered state <state>. Execution ID: <exec_id>. Account: <account> Region: <region>\""
  }
}

# Notify on pipeline successes (optional — useful for audit trail)
resource "aws_cloudwatch_event_rule" "pipeline_succeeded" {
  name        = "terraform-pipeline-succeeded"
  description = "Fires when the terraform-infra-pipeline execution succeeds"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      pipeline = [aws_codepipeline.terraform_pipeline.name]
      state    = ["SUCCEEDED"]
    }
  })

  tags = {
    Name        = "terraform-pipeline-succeeded"
    Environment = "prod"
  }
}

resource "aws_cloudwatch_event_target" "pipeline_succeeded_sns" {
  rule      = aws_cloudwatch_event_rule.pipeline_succeeded.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.pipeline_alerts.arn

  input_transformer {
    input_paths = {
      pipeline = "$.detail.pipeline"
      state    = "$.detail.state"
      exec_id  = "$.detail.execution-id"
    }

    input_template = "\"Pipeline <pipeline> completed successfully. Execution ID: <exec_id>\""
  }
}

# Notify when a build stage (validate or apply) fails
resource "aws_cloudwatch_event_rule" "build_failed" {
  name        = "terraform-codebuild-failed"
  description = "Fires when a terraform CodeBuild project build fails"

  event_pattern = jsonencode({
    source      = ["aws.codebuild"]
    detail-type = ["CodeBuild Build State Change"]
    detail = {
      "project-name" = [
        aws_codebuild_project.terraform_validate.name,
        aws_codebuild_project.terraform_apply.name
      ]
      "build-status" = ["FAILED"]
    }
  })

  tags = {
    Name        = "terraform-codebuild-failed"
    Environment = "prod"
  }
}

resource "aws_cloudwatch_event_target" "build_failed_sns" {
  rule      = aws_cloudwatch_event_rule.build_failed.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.pipeline_alerts.arn

  input_transformer {
    input_paths = {
      project  = "$.detail.project-name"
      status   = "$.detail.build-status"
      build_id = "$.detail.build-id"
    }

    input_template = "\"CodeBuild project <project> build <build_id> finished with status: <status>\""
  }
}

# ─── CloudWatch Alarms ────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "validate_build_failures" {
  alarm_name          = "terraform-validate-build-failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedBuilds"
  namespace           = "AWS/CodeBuild"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Triggered when the terraform-validate-plan CodeBuild project has a failed build"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.pipeline_alerts.arn]
  ok_actions          = [aws_sns_topic.pipeline_alerts.arn]

  dimensions = {
    ProjectName = aws_codebuild_project.terraform_validate.name
  }

  tags = {
    Name        = "terraform-validate-build-failures"
    Environment = "prod"
  }
}

resource "aws_cloudwatch_metric_alarm" "apply_build_failures" {
  alarm_name          = "terraform-apply-build-failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedBuilds"
  namespace           = "AWS/CodeBuild"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Triggered when the terraform-apply CodeBuild project has a failed build"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.pipeline_alerts.arn]
  ok_actions          = [aws_sns_topic.pipeline_alerts.arn]

  dimensions = {
    ProjectName = aws_codebuild_project.terraform_apply.name
  }

  tags = {
    Name        = "terraform-apply-build-failures"
    Environment = "prod"
  }
}

resource "aws_cloudwatch_metric_alarm" "validate_build_duration" {
  alarm_name          = "terraform-validate-build-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/CodeBuild"
  period              = 300
  statistic           = "Average"
  threshold           = 1200000 # 20 minutes in milliseconds
  alarm_description   = "Triggered when validate/plan builds take longer than 20 minutes"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.pipeline_alerts.arn]

  dimensions = {
    ProjectName = aws_codebuild_project.terraform_validate.name
  }

  tags = {
    Name        = "terraform-validate-build-duration"
    Environment = "prod"
  }
}

# ─── CloudWatch Dashboard ─────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "terraform_pipeline" {
  dashboard_name = "TerraformInfraPipeline"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# Terraform Infrastructure Pipeline"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "CodeBuild – Validate/Plan: Succeeded vs Failed"
          region = "us-east-1"
          metrics = [
            ["AWS/CodeBuild", "SucceededBuilds", "ProjectName", aws_codebuild_project.terraform_validate.name, { "stat" : "Sum", "color" : "#2ca02c" }],
            ["AWS/CodeBuild", "FailedBuilds", "ProjectName", aws_codebuild_project.terraform_validate.name, { "stat" : "Sum", "color" : "#d62728" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "CodeBuild – Apply: Succeeded vs Failed"
          region = "us-east-1"
          metrics = [
            ["AWS/CodeBuild", "SucceededBuilds", "ProjectName", aws_codebuild_project.terraform_apply.name, { "stat" : "Sum", "color" : "#2ca02c" }],
            ["AWS/CodeBuild", "FailedBuilds", "ProjectName", aws_codebuild_project.terraform_apply.name, { "stat" : "Sum", "color" : "#d62728" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "CodeBuild – Build Duration (ms)"
          region = "us-east-1"
          metrics = [
            ["AWS/CodeBuild", "Duration", "ProjectName", aws_codebuild_project.terraform_validate.name, { "stat" : "Average", "label" : "Validate/Plan avg" }],
            ["AWS/CodeBuild", "Duration", "ProjectName", aws_codebuild_project.terraform_apply.name, { "stat" : "Average", "label" : "Apply avg" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      },
      {
        type   = "alarm"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title = "Active Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.validate_build_failures.arn,
            aws_cloudwatch_metric_alarm.apply_build_failures.arn,
            aws_cloudwatch_metric_alarm.validate_build_duration.arn
          ]
        }
      }
    ]
  })
}

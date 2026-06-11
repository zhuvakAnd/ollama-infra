# ─── CloudWatch Log Groups ────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "codebuild_validate" {
  name              = "/codebuild/terraform-validate-plan"
  retention_in_days = 14

  tags = {
    Name        = "codebuild-terraform-validate"
    Environment = "prod"
  }
}

resource "aws_cloudwatch_log_group" "codebuild_apply" {
  name              = "/codebuild/terraform-apply"
  retention_in_days = 14

  tags = {
    Name        = "codebuild-terraform-apply"
    Environment = "prod"
  }
}

# ─── CodeBuild: Terraform Validate & Plan ────────────────────────────────────

resource "aws_codebuild_project" "terraform_validate" {
  name          = "terraform-validate-plan"
  description   = "Runs terraform fmt, validate, and plan; outputs tfplan artifact"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 30

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "TF_IN_AUTOMATION"
      value = "true"
    }

    environment_variable {
      name  = "TF_WORKING_DIR"
      value = "main"
    }

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = "tfstate-542776677488-eu-north-1-an"
    }

    environment_variable {
      name  = "TF_STATE_REGION"
      value = "eu-north-1"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-terraform.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild_validate.name
      stream_name = "build"
      status      = "ENABLED"
    }
  }

  tags = {
    Name        = "terraform-validate-plan"
    Environment = "prod"
  }

  depends_on = [
    aws_iam_role_policy_attachment.codebuild_admin,
    aws_iam_role_policy.codebuild_s3_state,
    aws_cloudwatch_log_group.codebuild_validate
  ]
}

# ─── CodeBuild: Terraform Apply ───────────────────────────────────────────────

resource "aws_codebuild_project" "terraform_apply" {
  name          = "terraform-apply"
  description   = "Runs terraform apply using the saved plan from the Validate stage"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 60

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "TF_IN_AUTOMATION"
      value = "true"
    }

    environment_variable {
      name  = "TF_WORKING_DIR"
      value = "main"
    }

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = "tfstate-542776677488-eu-north-1-an"
    }

    environment_variable {
      name  = "TF_STATE_REGION"
      value = "eu-north-1"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-terraform-apply.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild_apply.name
      stream_name = "build"
      status      = "ENABLED"
    }
  }

  tags = {
    Name        = "terraform-apply"
    Environment = "prod"
  }

  depends_on = [
    aws_iam_role_policy_attachment.codebuild_admin,
    aws_iam_role_policy.codebuild_s3_state,
    aws_cloudwatch_log_group.codebuild_apply
  ]
}

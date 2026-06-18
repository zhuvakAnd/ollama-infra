# ─── S3 Artifact Bucket ───────────────────────────────────────────────────────

resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket        = "codepipeline-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name        = "codepipeline-artifacts"
    Environment = "prod"
  }
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# ─── SNS – Manual Approval Notifications ──────────────────────────────────────

resource "aws_sns_topic" "pipeline_approval" {
  name = "terraform-pipeline-approval"

  tags = {
    Name        = "terraform-pipeline-approval"
    Environment = "prod"
  }
}

resource "aws_sns_topic_subscription" "pipeline_approval_email" {
  count = var.approval_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.pipeline_approval.arn
  protocol  = "email"
  endpoint  = var.approval_email
}

# ─── CodePipeline – Infrastructure Pipeline ───────────────────────────────────

resource "aws_codepipeline" "terraform_pipeline" {
  name           = "terraform-infra-pipeline"
  role_arn       = aws_iam_role.codepipeline_role.arn
  pipeline_type  = "V2"
  execution_mode = "SUPERSEDED"

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  # Trigger only when files under main/ change
  trigger {
    provider_type = "CodeStarSourceConnection"

    git_configuration {
      source_action_name = "Source"

      push {
        branches {
          includes = ["main"]
        }

        # file_paths {
        #   includes = ["main/*"]
        # }
      }
    }
  }

  # ── Stage 1: Source ──────────────────────────────────────────────────────────
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_artifact"]

      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = var.github_repo
        BranchName           = "main"
        OutputArtifactFormat = "CODE_ZIP"
        DetectChanges        = "false" # V2 trigger block handles change detection
      }
    }
  }

  # ── Stage 2: Validate & Plan ─────────────────────────────────────────────────
  stage {
    name = "Validate"

    action {
      name             = "Terraform-Validate-Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_artifact"]
      output_artifacts = ["plan_artifact"]

      configuration = {
        ProjectName = aws_codebuild_project.terraform_validate.name
      }
    }
  }

  # ── Stage 3: Manual Approval ─────────────────────────────────────────────────
  stage {
    name = "Approval"

    action {
      name     = "Manual-Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn    = aws_sns_topic.pipeline_approval.arn
        CustomData         = "Review the Terraform plan output in CodeBuild logs before approving. Rejecting will stop the deployment."
        ExternalEntityLink = "https://console.aws.amazon.com/codesuite/codebuild/projects/terraform-validate-plan/history"
      }
    }
  }

  # ── Stage 4: Deploy ──────────────────────────────────────────────────────────
  stage {
    name = "Deploy"

    action {
      name            = "Terraform-Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_artifact", "plan_artifact"]

      configuration = {
        ProjectName   = aws_codebuild_project.terraform_apply.name
        PrimarySource = "source_artifact"
      }
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.codepipeline_managed,
    aws_iam_role_policy.codepipeline_s3,
    aws_iam_role_policy.codepipeline_codebuild,
    aws_iam_role_policy.codestar_connection,
    aws_iam_role_policy.codepipeline_sns,
    aws_s3_bucket_versioning.pipeline_artifacts
  ]
}

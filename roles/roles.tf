resource "aws_iam_role" "codebuild_role" {
  name = "CodeBuildServiceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_ecr" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"

  depends_on = [aws_iam_role.codebuild_role]
}

resource "aws_iam_role_policy_attachment" "codebuild_logs" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"

  depends_on = [aws_iam_role.codebuild_role]
}

resource "aws_iam_role" "codepipeline_role" {
  name = "CodePipelineServiceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_managed" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"

  depends_on = [aws_iam_role.codepipeline_role]
}

resource "aws_iam_role_policy" "codepipeline_codebuild_extended" {
  name = "CodePipelineCodeBuildExtended"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:BatchGetBuildBatches",
          "codebuild:StartBuild",
          "codebuild:StartBuildBatch",
          "codebuild:StopBuild",
          "codebuild:StopBuildBatch",
          "codebuild:RetryBuild",
          "codebuild:RetryBuildBatch",
          "codebuild:ListBuildsForProject"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_iam_role.codepipeline_role]
}

resource "aws_iam_role_policy" "codestar_connection" {
  name = "CodeStarConnectionsFullAccess"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codeconnections:*",
          "codestar-connections:UseConnection",
          "codestar-connections:GetConnection"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_iam_role.codepipeline_role]
}

resource "aws_iam_role_policy" "codepipeline_s3" {
  name = "CodePipelineS3ArtifactAccess"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetBucketVersioning",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::codepipeline-artifacts-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::codepipeline-artifacts-${data.aws_caller_identity.current.account_id}/*"
        ]
      }
    ]
  })

  depends_on = [aws_iam_role.codepipeline_role]
}

resource "aws_iam_role_policy" "codepipeline_codebuild" {
  name = "CodePipelineCodeBuildAccess"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:StopBuild"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_iam_role.codepipeline_role]
}

resource "aws_iam_role_policy" "codepipeline_sns" {
  name = "CodePipelineSNSApproval"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.pipeline_approval.arn
      }
    ]
  })

  depends_on = [aws_iam_role.codepipeline_role]
}

resource "aws_iam_role" "codedeploy_role" {
  name = "CodeDeployServiceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_managed" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"

  depends_on = [aws_iam_role.codedeploy_role]
}

# AdministratorAccess is needed so Terraform can manage all infrastructure resources.
# Scope this down once the full set of managed resources is stable.
resource "aws_iam_role_policy_attachment" "codebuild_admin" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"

  depends_on = [aws_iam_role.codebuild_role]
}

resource "aws_iam_role_policy" "codebuild_self" {
  name = "CodeBuildSelfReporting"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CodeBuildReports"
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ]
        Resource = "arn:aws:codebuild:us-east-1:${data.aws_caller_identity.current.account_id}:report-group/*"
      },
      {
        Sid    = "CodeBuildSSMParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/*"
      }
    ]
  })

  depends_on = [aws_iam_role.codebuild_role]
}

resource "aws_iam_role_policy" "codebuild_s3_state" {
  name = "CodeBuildTerraformStateAccess"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          "arn:aws:s3:::terraform-state-058264468006-eu-north-1-an",
          "arn:aws:s3:::terraform-state-058264468006-eu-north-1-an/*",
          "arn:aws:s3:::codepipeline-artifacts-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::codepipeline-artifacts-${data.aws_caller_identity.current.account_id}/*"
        ]
      }
    ]
  })

  depends_on = [aws_iam_role.codebuild_role]
}


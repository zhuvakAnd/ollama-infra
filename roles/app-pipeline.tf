# ─── CloudWatch Log Group for Docker Build ───────────────────────────────────

resource "aws_cloudwatch_log_group" "codebuild_docker" {
  name              = "/codebuild/docker-image-build"
  retention_in_days = 14

  tags = {
    Name        = "codebuild-docker-build"
    Environment = "prod"
  }
}

# ─── CodeDeploy Application ───────────────────────────────────────────────────
# The application is a permanent, free resource.
# The deployment group (which references ECS + ALB) lives in main/ so it can
# be destroyed together with the compute resources.

resource "aws_codedeploy_app" "ecs_app" {
  name             = "ollama-ecs-app"
  compute_platform = "ECS"
}

# ─── CodeBuild: Docker Image Build ────────────────────────────────────────────

resource "aws_codebuild_project" "docker_build" {
  name          = "docker-image-build"
  description   = "Builds and pushes the Ollama Docker image to ECR; outputs imageDetail.json and taskdef.json"
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
    privileged_mode             = true # required for Docker daemon access

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = "us-east-1"
    }

    environment_variable {
      name  = "ECR_REPO_URI"
      value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com/ollama-app"
    }

    environment_variable {
      name  = "ECS_CLUSTER"
      value = "ollama-fargate-cluster"
    }

    environment_variable {
      name  = "ECS_SERVICE"
      value = "ollama-webui-service"
    }

    environment_variable {
      name  = "CONTAINER_NAME"
      value = "ollama"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-docker.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild_docker.name
      stream_name = "build"
      status      = "ENABLED"
    }
  }

  tags = {
    Name        = "docker-image-build"
    Environment = "prod"
  }

  depends_on = [
    aws_iam_role_policy_attachment.codebuild_admin,
    aws_cloudwatch_log_group.codebuild_docker
  ]
}

# ─── CodePipeline: Application Pipeline ──────────────────────────────────────

resource "aws_codepipeline" "app_pipeline" {
  name           = "application-pipeline"
  role_arn       = aws_iam_role.codepipeline_role.arn
  pipeline_type  = "V2"
  execution_mode = "SUPERSEDED"

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  # Trigger only when Tinyllama.Dockerfile changes on the infrastructure branch
  trigger {
    provider_type = "CodeStarSourceConnection"

    git_configuration {
      source_action_name = "Source"

      push {
        branches {
          includes = ["main"]
        }

        file_paths {
          includes = ["docker/Tinyllama.Dockerfile"]
        }
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
        DetectChanges        = "false"
      }
    }
  }

  # ── Stage 2: Build Docker Image ──────────────────────────────────────────────
  stage {
    name = "Build"

    action {
      name             = "Docker-Image-Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_artifact"]
      output_artifacts = ["build_artifact"]

      configuration = {
        ProjectName = aws_codebuild_project.docker_build.name
      }
    }
  }

  # ── Stage 3: ECS Blue/Green Deploy via CodeDeploy ────────────────────────────
  # ApplicationName and DeploymentGroupName are hardcoded so this pipeline
  # requires no data sources pointing at main/ stack resources.
  # The deployment group is created in main/codedeploy.tf and must exist
  # before the pipeline can successfully execute a deployment.
  stage {
    name = "Deploy"

    action {
      name            = "ECS-BlueGreen-Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["source_artifact", "build_artifact"]

      configuration = {
        ApplicationName                = "ollama-ecs-app"
        DeploymentGroupName            = "ollama-ecs-deployment-group"
        TaskDefinitionTemplateArtifact = "build_artifact"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "source_artifact"
        AppSpecTemplatePath            = "appspec.yml"
        Image1ArtifactName             = "build_artifact"
        Image1ContainerName            = "ollama"
      }
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.codepipeline_managed,
    aws_iam_role_policy.codepipeline_s3,
    aws_iam_role_policy.codepipeline_codebuild_extended,
    aws_iam_role_policy.codestar_connection,
    aws_s3_bucket_versioning.pipeline_artifacts
  ]
}

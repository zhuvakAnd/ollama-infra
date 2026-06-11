# The CodeDeploy *application* lives in roles/ (free, permanent).
# The deployment *group* lives here because it is tightly coupled to the
# ECS service, ALB listener, and target groups — all of which are destroyed
# together with this stack when not in use.

data "aws_iam_role" "codedeploy" {
  name = "CodeDeployServiceRole"
}

resource "aws_codedeploy_deployment_group" "ecs_dg" {
  app_name              = "ollama-ecs-app"
  deployment_group_name = "ollama-ecs-deployment-group"
  service_role_arn      = data.aws_iam_role.codedeploy.arn

  # All at once — swap 100% of traffic in a single step.
  # Alternatives: CodeDeployDefault.ECSCanary10Percent5Minutes
  #               CodeDeployDefault.ECSLinear10PercentEvery1Minutes
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_REQUEST"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.ollama_cluster.name
    service_name = aws_ecs_service.ollama_service.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }

      target_group {
        name = aws_lb_target_group.webui_tg.name
      }

      target_group {
        name = aws_lb_target_group.webui_tg_green.name
      }
    }
  }

  depends_on = [
    aws_ecs_service.ollama_service,
    aws_lb_listener.http
  ]
}

resource "aws_ecr_repository" "ollama_app" {
  name                 = "ollama-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name = "ollama-app"
  }
}

resource "aws_ecr_lifecycle_policy" "ollama_app_policy" {
  repository = aws_ecr_repository.ollama_app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

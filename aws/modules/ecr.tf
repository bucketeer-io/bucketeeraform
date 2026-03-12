# ECR repositories for Bucketeer images (build and push your images here)

resource "aws_ecr_repository" "api" {
  name                 = "${var.app_name}/api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = { Name = "${var.app_name}-api" }
}

resource "aws_ecr_repository" "web" {
  name                 = "${var.app_name}/web"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = { Name = "${var.app_name}-web" }
}

resource "aws_ecr_repository" "batch" {
  name                 = "${var.app_name}/batch"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = { Name = "${var.app_name}-batch" }
}

resource "aws_ecr_repository" "nginx" {
  name                 = "${var.app_name}/nginx"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = { Name = "${var.app_name}-nginx" }
}

resource "aws_ecr_repository" "subscriber" {
  name                 = "${var.app_name}/subscriber"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = { Name = "${var.app_name}-subscriber" }
}

resource "aws_ecr_lifecycle_policy" "keep_last_5" {
  for_each = toset([aws_ecr_repository.api.name, aws_ecr_repository.web.name, aws_ecr_repository.batch.name, aws_ecr_repository.nginx.name, aws_ecr_repository.subscriber.name])

  repository = each.key

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# DB password in Secrets Manager (ECS tasks pull via task definition secrets)

resource "aws_secretsmanager_secret" "db_password" {
  name        = "${local.name}/database-password"
  description = "RDS MySQL password for Bucketeer"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

# Allow ECS task execution role to read the secret
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${local.name}-ecs-execution-secrets"
  role = aws_iam_role.ecs_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.db_password.arn]
    }]
  })
}

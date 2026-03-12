output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (use this to access Bucketeer)"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Route53 zone ID of the ALB (for CNAME if using custom domain)"
  value       = aws_lb.main.zone_id
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint (for migrations or debugging)"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecr_api_url" {
  description = "ECR repository URL for API image"
  value       = aws_ecr_repository.api.repository_url
}

output "ecr_web_url" {
  description = "ECR repository URL for Web image"
  value       = aws_ecr_repository.web.repository_url
}

output "ecr_batch_url" {
  description = "ECR repository URL for Batch image"
  value       = aws_ecr_repository.batch.repository_url
}

output "ecr_nginx_url" {
  description = "ECR repository URL for Nginx image"
  value       = aws_ecr_repository.nginx.repository_url
}

output "ecr_subscriber_url" {
  description = "ECR repository URL for Subscriber image"
  value       = aws_ecr_repository.subscriber.repository_url
}

output "app_url" {
  description = "URL to access Bucketeer (HTTP)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "pre_migration_task_definition_arn" {
  description = "ARN of the pre-migration ECS task definition"
  value       = aws_ecs_task_definition.pre_migration.arn
}

output "migration_task_definition_arn" {
  description = "ARN of the migration ECS task definition"
  value       = aws_ecs_task_definition.migration.arn
}

output "ecs_subnet_ids" {
  description = "Subnet IDs for ECS tasks (used by run-task)"
  value       = join(",", aws_subnet.public[*].id)
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs.id
}

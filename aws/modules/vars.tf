variable "aws_region" {
  description = "AWS region (use us-east-1 for best free tier coverage)"
  type        = string
  default     = "us-east-1"
}

variable "aws_access_key_id" {
  description = "AWS access key (leave empty to use default credential chain)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key (leave empty to use default credential chain)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "app_name" {
  description = "Application name prefix for resources"
  type        = string
  default     = "bucketeer"
}

# RDS MySQL
variable "db_allocated_storage" {
  description = "RDS allocated storage (GB). Free tier: 20 GB."
  type        = number
  default     = 20
}

variable "db_instance_class" {
  description = "RDS instance class. Free tier: db.t3.micro or db.t4g.micro"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "MySQL database name"
  type        = string
  default     = "bucketeer"
}

variable "db_username" {
  description = "MySQL master username"
  type        = string
  default     = "bucketeer"
}

variable "db_password" {
  description = "MySQL master password"
  type        = string
  sensitive   = true
}

# ElastiCache Redis
variable "redis_node_type" {
  description = "ElastiCache node type. Free tier: cache.t3.micro or cache.t4g.micro"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_clusters" {
  description = "Number of Redis nodes (1 for free tier / minimal cost)"
  type        = number
  default     = 1
}

# ECS
variable "ecs_cpu" {
  description = "CPU units per task (256 = 0.25 vCPU, Fargate min)"
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "Memory per task in MB (512 = Fargate min)"
  type        = number
  default     = 512
}

variable "bucketeer_version" {
  description = "Bucketeer release version (used for app images and migration)"
  type        = string
  default     = "v2.2.0"
}

# Optional
variable "domain_name" {
  description = "Optional domain for ALB (ACM cert and route53)"
  type        = string
  default     = ""
}

variable "create_nat_gateway" {
  description = "Create NAT gateway for private subnets (costs ~$32/mo)"
  type        = bool
  default     = false
}

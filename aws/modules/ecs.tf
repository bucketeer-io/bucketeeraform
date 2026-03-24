# ECS cluster, service discovery, task definitions, and services

locals {
  redis_host = aws_elasticache_replication_group.main.primary_endpoint_address
  # address = hostname only; endpoint = "host:port". App expects MYSQL_HOST + MYSQL_PORT separately.
  mysql_host = aws_db_instance.main.address
  namespace  = "bucketeer.local"
}

# Log group for ECS tasks
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7
}

# ECS cluster
resource "aws_ecs_cluster" "main" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

# Task execution role (ECR pull, CloudWatch logs)
resource "aws_iam_role" "ecs_execution" {
  name = "${local.name}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role (for app; can add S3 etc. later)
resource "aws_iam_role" "ecs_task" {
  name = "${local.name}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Service discovery (private DNS so tasks can resolve web, api, batch, subscriber, nginx)
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = local.namespace
  vpc         = aws_vpc.main.id
  description = "Bucketeer service discovery"
}

resource "aws_service_discovery_service" "web" {
  name = "web"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "api" {
  name = "api"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "batch" {
  name = "batch"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "subscriber" {
  name = "subscriber"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "nginx" {
  name = "nginx"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

# Task definition: API
resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "api"
    image     = "${aws_ecr_repository.api.repository_url}:${var.bucketeer_version}"
    essential = true
    portMappings = [
      { containerPort = 9090, protocol = "tcp" },
      { containerPort = 9089, protocol = "tcp" },
      { containerPort = 9002, protocol = "tcp" }
    ]
    environment = [
      { name = "BUCKETEER_API_PROJECT", value = local.name },
      { name = "BUCKETEER_API_STORAGE_TYPE", value = "mysql" },
      { name = "BUCKETEER_API_MYSQL_USER", value = var.db_username },
      { name = "BUCKETEER_API_MYSQL_HOST", value = local.mysql_host },
      { name = "BUCKETEER_API_MYSQL_PORT", value = "3306" },
      { name = "BUCKETEER_API_MYSQL_DB_NAME", value = var.db_name },
      { name = "BUCKETEER_API_GOAL_TOPIC", value = "goal" },
      { name = "BUCKETEER_API_EVALUATION_TOPIC", value = "evaluation" },
      { name = "BUCKETEER_API_USER_TOPIC", value = "user" },
      { name = "BUCKETEER_API_METRICS_TOPIC", value = "metrics" },
      { name = "BUCKETEER_API_PUBLISH_NUM_GOROUTINES", value = "200" },
      { name = "BUCKETEER_API_PUBLISH_TIMEOUT", value = "1m" },
      { name = "BUCKETEER_API_REDIS_SERVER_NAME", value = "api-gateway" },
      { name = "BUCKETEER_API_REDIS_ADDR", value = "${local.redis_host}:6379" },
      { name = "BUCKETEER_API_REDIS_POOL_MAX_IDLE", value = "25" },
      { name = "BUCKETEER_API_REDIS_POOL_MAX_ACTIVE", value = "25" },
      { name = "BUCKETEER_API_REDIS_MODE", value = "auto" },
      { name = "BUCKETEER_API_PUBSUB_TYPE", value = "redis-stream" },
      { name = "BUCKETEER_API_PUBSUB_REDIS_SERVER_NAME", value = "non-persistent-redis" },
      { name = "BUCKETEER_API_PUBSUB_REDIS_ADDR", value = "${local.redis_host}:6379" },
      { name = "BUCKETEER_API_PUBSUB_REDIS_POOL_SIZE", value = "25" },
      { name = "BUCKETEER_API_PUBSUB_REDIS_MIN_IDLE", value = "25" },
      { name = "BUCKETEER_API_PUBSUB_REDIS_PARTITION_COUNT", value = "16" },
      { name = "BUCKETEER_API_PUBSUB_REDIS_MODE", value = "auto" },
      { name = "BUCKETEER_API_OLDEST_EVENT_TIMESTAMP", value = "24h" },
      { name = "BUCKETEER_API_FURTHEST_EVENT_TIMESTAMP", value = "24h" },
      { name = "BUCKETEER_API_PORT", value = "9090" },
      { name = "BUCKETEER_API_GRPC_GATEWAY_PORT", value = "9089" },
      { name = "BUCKETEER_API_METRICS_PORT", value = "9002" },
      { name = "BUCKETEER_API_CERT", value = "/usr/local/certs/service/tls.crt" },
      { name = "BUCKETEER_API_KEY", value = "/usr/local/certs/service/tls.key" },
      { name = "BUCKETEER_API_SERVICE_TOKEN", value = "/usr/local/service-token/token" },
      { name = "BUCKETEER_API_FEATURE_SERVICE", value = "web.${local.namespace}:9098" },
      { name = "BUCKETEER_API_ACCOUNT_SERVICE", value = "web.${local.namespace}:9091" },
      { name = "BUCKETEER_API_PUSH_SERVICE", value = "web.${local.namespace}:9101" },
      { name = "BUCKETEER_API_CODE_REF_SERVICE", value = "web.${local.namespace}:9105" },
      { name = "BUCKETEER_API_AUDIT_LOG_SERVICE", value = "web.${local.namespace}:9093" },
      { name = "BUCKETEER_API_TAG_SERVICE", value = "web.${local.namespace}:9104" },
      { name = "BUCKETEER_API_TEAM_SERVICE", value = "web.${local.namespace}:9107" },
      { name = "BUCKETEER_API_NOTIFICATION_SERVICE", value = "web.${local.namespace}:9100" },
      { name = "BUCKETEER_API_EXPERIMENT_SERVICE", value = "web.${local.namespace}:9097" },
      { name = "BUCKETEER_API_EVENT_COUNTER_SERVICE", value = "web.${local.namespace}:9096" },
      { name = "BUCKETEER_API_ENVIRONMENT_SERVICE", value = "web.${local.namespace}:9095" },
      { name = "BUCKETEER_API_LOG_LEVEL", value = "info" },
      { name = "BUCKETEER_API_PROFILE", value = "false" },
      { name = "BUCKETEER_API_GCP_TRACE_ENABLED", value = "false" },
      { name = "BUCKETEER_API_TRACE_SAMPLING_PROBABILITY", value = "0.0" }
    ]
    secrets = [
      { name = "BUCKETEER_API_MYSQL_PASS", valueFrom = aws_secretsmanager_secret.db_password.arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "api"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "wget -q -O- http://localhost:9090/health || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 5
      startPeriod = 120
    }
  }])
}

# Task definition: Web
resource "aws_ecs_task_definition" "web" {
  family                   = "${local.name}-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "web"
    image     = "${aws_ecr_repository.web.repository_url}:${var.bucketeer_version}"
    essential = true
    portMappings = [
      { containerPort = 9089, protocol = "tcp" },
      { containerPort = 8000, protocol = "tcp" },
      { containerPort = 9091, protocol = "tcp" },
      { containerPort = 9092, protocol = "tcp" },
      { containerPort = 9093, protocol = "tcp" },
      { containerPort = 9094, protocol = "tcp" },
      { containerPort = 9095, protocol = "tcp" },
      { containerPort = 9096, protocol = "tcp" },
      { containerPort = 9097, protocol = "tcp" },
      { containerPort = 9098, protocol = "tcp" },
      { containerPort = 9100, protocol = "tcp" },
      { containerPort = 9101, protocol = "tcp" },
      { containerPort = 9102, protocol = "tcp" },
      { containerPort = 9103, protocol = "tcp" },
      { containerPort = 9104, protocol = "tcp" },
      { containerPort = 9105, protocol = "tcp" },
      { containerPort = 9107, protocol = "tcp" },
      { containerPort = 9002, protocol = "tcp" }
    ]
    environment = [
      { name = "BUCKETEER_TEST_ENABLED", value = "true" },
      { name = "BUCKETEER_WEB_STORAGE_TYPE", value = "mysql" },
      { name = "BUCKETEER_WEB_MYSQL_USER", value = var.db_username },
      { name = "BUCKETEER_WEB_MYSQL_HOST", value = local.mysql_host },
      { name = "BUCKETEER_WEB_MYSQL_PORT", value = "3306" },
      { name = "BUCKETEER_WEB_MYSQL_DB_NAME", value = var.db_name },
      { name = "BUCKETEER_WEB_PERSISTENT_REDIS_SERVER_NAME", value = "persistent-redis" },
      { name = "BUCKETEER_WEB_PERSISTENT_REDIS_ADDR", value = "${local.redis_host}:6379" },
      { name = "BUCKETEER_WEB_PERSISTENT_REDIS_POOL_MAX_IDLE", value = "25" },
      { name = "BUCKETEER_WEB_PERSISTENT_REDIS_POOL_MAX_ACTIVE", value = "25" },
      { name = "BUCKETEER_WEB_PERSISTENT_REDIS_MODE", value = "auto" },
      { name = "BUCKETEER_WEB_NON_PERSISTENT_REDIS_SERVER_NAME", value = "non-persistent-redis" },
      { name = "BUCKETEER_WEB_NON_PERSISTENT_REDIS_ADDR", value = "${local.redis_host}:6379" },
      { name = "BUCKETEER_WEB_NON_PERSISTENT_REDIS_POOL_MAX_IDLE", value = "25" },
      { name = "BUCKETEER_WEB_NON_PERSISTENT_REDIS_POOL_MAX_ACTIVE", value = "25" },
      { name = "BUCKETEER_WEB_NON_PERSISTENT_REDIS_MODE", value = "auto" },
      { name = "BUCKETEER_WEB_PUBSUB_TYPE", value = "redis-stream" },
      { name = "BUCKETEER_WEB_PUBSUB_REDIS_SERVER_NAME", value = "non-persistent-redis" },
      { name = "BUCKETEER_WEB_PUBSUB_REDIS_ADDR", value = "${local.redis_host}:6379" },
      { name = "BUCKETEER_WEB_PUBSUB_REDIS_POOL_SIZE", value = "25" },
      { name = "BUCKETEER_WEB_PUBSUB_REDIS_MIN_IDLE", value = "25" },
      { name = "BUCKETEER_WEB_PUBSUB_REDIS_PARTITION_COUNT", value = "16" },
      { name = "BUCKETEER_WEB_PUBSUB_REDIS_MODE", value = "auto" },
      { name = "BUCKETEER_WEB_PROJECT", value = local.name },
      { name = "BUCKETEER_WEB_DOMAIN_TOPIC", value = "domain" },
      { name = "BUCKETEER_WEB_BULK_SEGMENT_USERS_RECEIVED_TOPIC", value = "bulk-segment-users-received" },
      { name = "BUCKETEER_WEB_GRPC_GATEWAY_PORT", value = "9089" },
      { name = "BUCKETEER_WEB_HEALTH_CHECK_SERVICE_PORT", value = "8000" },
      { name = "BUCKETEER_WEB_ACCOUNT_SERVICE_PORT", value = "9091" },
      { name = "BUCKETEER_WEB_AUTH_SERVICE_PORT", value = "9092" },
      { name = "BUCKETEER_WEB_AUDIT_LOG_SERVICE_PORT", value = "9093" },
      { name = "BUCKETEER_WEB_AUTO_OPS_SERVICE_PORT", value = "9094" },
      { name = "BUCKETEER_WEB_ENVIRONMENT_SERVICE_PORT", value = "9095" },
      { name = "BUCKETEER_WEB_EVENT_COUNTER_SERVICE_PORT", value = "9096" },
      { name = "BUCKETEER_WEB_EXPERIMENT_SERVICE_PORT", value = "9097" },
      { name = "BUCKETEER_WEB_FEATURE_SERVICE_PORT", value = "9098" },
      { name = "BUCKETEER_WEB_NOTIFICATION_SERVICE_PORT", value = "9100" },
      { name = "BUCKETEER_WEB_PUSH_SERVICE_PORT", value = "9101" },
      { name = "BUCKETEER_WEB_TAG_SERVICE_PORT", value = "9104" },
      { name = "BUCKETEER_WEB_TEAM_SERVICE_PORT", value = "9107" },
      { name = "BUCKETEER_WEB_WEB_CONSOLE_SERVICE_PORT", value = "9102" },
      { name = "BUCKETEER_WEB_DASHBOARD_SERVICE_PORT", value = "9103" },
      { name = "BUCKETEER_WEB_CODE_REFERENCE_SERVICE_PORT", value = "9105" },
      { name = "BUCKETEER_WEB_UNIFIED_GATEWAY_PORT", value = "9106" },
      { name = "BUCKETEER_WEB_METRICS_PORT", value = "9002" },
      { name = "BUCKETEER_WEB_TIMEZONE", value = "UTC" },
      { name = "BUCKETEER_WEB_LOG_LEVEL", value = "info" },
      { name = "BUCKETEER_WEB_PROFILE", value = "false" },
      { name = "BUCKETEER_WEB_GCP_TRACE_ENABLED", value = "false" },
      { name = "BUCKETEER_WEB_USE_MYSQL", value = "true" },
      { name = "BUCKETEER_WEB_CLOUD_SERVICE", value = "gcp" },
      { name = "BUCKETEER_WEB_WEBHOOK_BASE_URL", value = "https://localhost" },
      { name = "BUCKETEER_WEB_WEBHOOK_KMS_RESOURCE_NAME", value = "vault" },
      { name = "BUCKETEER_WEB_OAUTH_PUBLIC_KEY", value = "/usr/local/oauth-key/public.pem" },
      { name = "BUCKETEER_WEB_OAUTH_PRIVATE_KEY", value = "/usr/local/oauth-key/private.pem" },
      { name = "BUCKETEER_WEB_OAUTH_CONFIG_PATH", value = "/usr/local/oauth-config/oauth-config.json" },
      { name = "BUCKETEER_WEB_EMAIL_CONFIG_PATH", value = "/usr/local/email-config/email-config.json" },
      { name = "BUCKETEER_WEB_CERT", value = "/usr/local/certs/service/tls.crt" },
      { name = "BUCKETEER_WEB_KEY", value = "/usr/local/certs/service/tls.key" },
      { name = "BUCKETEER_WEB_SERVICE_TOKEN", value = "/usr/local/service-token/token" },
      { name = "BUCKETEER_WEB_EMAIL_FILTER", value = "" },
      { name = "BUCKETEER_WEB_WEB_CONSOLE_ENV_JS_PATH", value = "/usr/local/static/js" },
      { name = "BUCKETEER_WEB_ACCOUNT_SERVICE", value = "nginx.${local.namespace}:443" },
      { name = "BUCKETEER_WEB_AUTH_SERVICE", value = "nginx.${local.namespace}:443" },
      { name = "BUCKETEER_WEB_BATCH_SERVICE", value = "nginx.${local.namespace}:443" },
      { name = "BUCKETEER_WEB_ENVIRONMENT_SERVICE", value = "nginx.${local.namespace}:443" },
      { name = "BUCKETEER_WEB_EXPERIMENT_SERVICE", value = "nginx.${local.namespace}:443" },
      { name = "BUCKETEER_WEB_FEATURE_SERVICE", value = "nginx.${local.namespace}:443" },
      { name = "BUCKETEER_WEB_AUTOOPS_SERVICE", value = "nginx.${local.namespace}:443" },
      { name = "BUCKETEER_WEB_CODE_REFERENCE_SERVICE", value = "nginx.${local.namespace}:443" },
      { name = "BUCKETEER_WEB_DATA_WAREHOUSE_CONFIG_PATH", value = "/usr/local/datawarehouse-config/datawarehouse.yaml" }
    ]
    secrets = [
      { name = "BUCKETEER_WEB_MYSQL_PASS", valueFrom = aws_secretsmanager_secret.db_password.arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "web"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "wget -q -O- http://localhost:8000/health || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 5
      startPeriod = 120
    }
  }])
}

# Task definition: Batch
resource "aws_ecs_task_definition" "batch" {
  family                   = "${local.name}-batch"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "batch"
    image     = "${aws_ecr_repository.batch.repository_url}:${var.bucketeer_version}"
    essential = true
    portMappings = [
      { containerPort = 9000, protocol = "tcp" },
      { containerPort = 9089, protocol = "tcp" },
      { containerPort = 9002, protocol = "tcp" }
    ]
    environment = [
      { name = "BUCKETEER_BATCH_PROJECT", value = local.name },
      { name = "BUCKETEER_BATCH_STORAGE_TYPE", value = "mysql" },
      { name = "BUCKETEER_BATCH_MYSQL_USER", value = var.db_username },
      { name = "BUCKETEER_BATCH_MYSQL_HOST", value = local.mysql_host },
      { name = "BUCKETEER_BATCH_MYSQL_PORT", value = "3306" },
      { name = "BUCKETEER_BATCH_MYSQL_DB_NAME", value = var.db_name },
      { name = "BUCKETEER_BATCH_MYSQL_DB_OPEN_CONNS", value = "50" },
      { name = "BUCKETEER_BATCH_PERSISTENT_REDIS_SERVER_NAME", value = "batch-persistent-redis" },
      { name = "BUCKETEER_BATCH_PERSISTENT_REDIS_ADDR", value = "${local.redis_host}:6379" },
      { name = "BUCKETEER_BATCH_PERSISTENT_REDIS_POOL_MAX_IDLE", value = "25" },
      { name = "BUCKETEER_BATCH_PERSISTENT_REDIS_POOL_MAX_ACTIVE", value = "25" },
      { name = "BUCKETEER_BATCH_PERSISTENT_REDIS_MODE", value = "auto" },
      { name = "BUCKETEER_BATCH_NON_PERSISTENT_REDIS_SERVER_NAME", value = "batch-non-persistent-redis" },
      { name = "BUCKETEER_BATCH_NON_PERSISTENT_REDIS_ADDR", value = "${local.redis_host}:6379" },
      { name = "BUCKETEER_BATCH_NON_PERSISTENT_REDIS_POOL_MAX_IDLE", value = "25" },
      { name = "BUCKETEER_BATCH_NON_PERSISTENT_REDIS_POOL_MAX_ACTIVE", value = "25" },
      { name = "BUCKETEER_BATCH_NON_PERSISTENT_REDIS_MODE", value = "auto" },
      { name = "BUCKETEER_BATCH_PUBSUB_TYPE", value = "redis-stream" },
      { name = "BUCKETEER_BATCH_PUBSUB_REDIS_SERVER_NAME", value = "non-persistent-redis" },
      { name = "BUCKETEER_BATCH_PUBSUB_REDIS_ADDR", value = "${local.redis_host}:6379" },
      { name = "BUCKETEER_BATCH_PUBSUB_REDIS_POOL_SIZE", value = "25" },
      { name = "BUCKETEER_BATCH_PUBSUB_REDIS_MIN_IDLE", value = "25" },
      { name = "BUCKETEER_BATCH_PUBSUB_REDIS_PARTITION_COUNT", value = "16" },
      { name = "BUCKETEER_BATCH_PORT", value = "9000" },
      { name = "BUCKETEER_BATCH_GRPC_GATEWAY_PORT", value = "9089" },
      { name = "BUCKETEER_BATCH_METRICS_PORT", value = "9002" },
      { name = "BUCKETEER_BATCH_TIMEZONE", value = "UTC" },
      { name = "BUCKETEER_BATCH_REFRESH_INTERVAL", value = "10m" },
      { name = "BUCKETEER_BATCH_EXPERIMENT_LOCK_TTL", value = "1m" },
      { name = "BUCKETEER_BATCH_WEB_URL", value = "http://localhost:3000" },
      { name = "BUCKETEER_BATCH_CERT", value = "/usr/local/certs/service/tls.crt" },
      { name = "BUCKETEER_BATCH_KEY", value = "/usr/local/certs/service/tls.key" },
      { name = "BUCKETEER_BATCH_SERVICE_TOKEN", value = "/usr/local/service-token/token" },
      { name = "BUCKETEER_BATCH_OAUTH_PUBLIC_KEY", value = "/usr/local/oauth-key/public.pem" },
      { name = "BUCKETEER_BATCH_OAUTH_ISSUER", value = "https://localhost" },
      { name = "BUCKETEER_BATCH_OAUTH_AUDIENCE", value = "bucketeer" },
      { name = "BUCKETEER_BATCH_OAUTH_CLIENT_ID", value = "" },
      { name = "BUCKETEER_BATCH_ACCOUNT_SERVICE", value = "web.${local.namespace}:9091" },
      { name = "BUCKETEER_BATCH_NOTIFICATION_SERVICE", value = "web.${local.namespace}:9100" },
      { name = "BUCKETEER_BATCH_ENVIRONMENT_SERVICE", value = "web.${local.namespace}:9095" },
      { name = "BUCKETEER_BATCH_PUSH_SERVICE", value = "web.${local.namespace}:9101" },
      { name = "BUCKETEER_BATCH_AUTO_OPS_SERVICE", value = "web.${local.namespace}:9094" },
      { name = "BUCKETEER_BATCH_EXPERIMENT_SERVICE", value = "web.${local.namespace}:9097" },
      { name = "BUCKETEER_BATCH_EVENT_COUNTER_SERVICE", value = "web.${local.namespace}:9096" },
      { name = "BUCKETEER_BATCH_FEATURE_SERVICE", value = "web.${local.namespace}:9098" },
      { name = "BUCKETEER_BATCH_BATCH_SERVICE", value = "nginx.${local.namespace}:443" },
      { name = "BUCKETEER_BATCH_LOG_LEVEL", value = "info" },
      { name = "BUCKETEER_BATCH_PROFILE", value = "false" },
      { name = "BUCKETEER_BATCH_GCP_TRACE_ENABLED", value = "false" },
      { name = "BUCKETEER_BATCH_STAN_MODEL_ID", value = "y3qsnd7m" },
      { name = "BUCKETEER_BATCH_STAN_HOST", value = "" },
      { name = "BUCKETEER_BATCH_STAN_PORT", value = "8080" }
    ]
    secrets = [
      { name = "BUCKETEER_BATCH_MYSQL_PASS", valueFrom = aws_secretsmanager_secret.db_password.arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "batch"
      }
    }
  }])
}

# Task definition: Subscriber
resource "aws_ecs_task_definition" "subscriber" {
  family                   = "${local.name}-subscriber"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "subscriber"
    image     = "${aws_ecr_repository.subscriber.repository_url}:${var.bucketeer_version}"
    essential = true
    portMappings = [
      { containerPort = 9000, protocol = "tcp" },
      { containerPort = 9002, protocol = "tcp" }
    ]
    environment = [
      { name = "BUCKETEER_SUBSCRIBER_PROJECT", value = local.name },
      { name = "BUCKETEER_SUBSCRIBER_STORAGE_TYPE", value = "mysql" },
      { name = "BUCKETEER_SUBSCRIBER_MYSQL_USER", value = var.db_username },
      { name = "BUCKETEER_SUBSCRIBER_MYSQL_HOST", value = local.mysql_host },
      { name = "BUCKETEER_SUBSCRIBER_MYSQL_PORT", value = "3306" },
      { name = "BUCKETEER_SUBSCRIBER_MYSQL_DB_NAME", value = var.db_name },
      { name = "BUCKETEER_SUBSCRIBER_MYSQL_DB_OPEN_CONNS", value = "50" },
      { name = "BUCKETEER_SUBSCRIBER_PERSISTENT_REDIS_SERVER_NAME", value = "batch-persistent-redis" },
      { name = "BUCKETEER_SUBSCRIBER_PERSISTENT_REDIS_ADDR", value = "${local.redis_host}:6379" },
      { name = "BUCKETEER_SUBSCRIBER_PERSISTENT_REDIS_POOL_MAX_IDLE", value = "25" },
      { name = "BUCKETEER_SUBSCRIBER_PERSISTENT_REDIS_POOL_MAX_ACTIVE", value = "25" },
      { name = "BUCKETEER_SUBSCRIBER_PERSISTENT_REDIS_MODE", value = "auto" },
      { name = "BUCKETEER_SUBSCRIBER_NON_PERSISTENT_REDIS_SERVER_NAME", value = "batch-non-persistent-redis" },
      { name = "BUCKETEER_SUBSCRIBER_NON_PERSISTENT_REDIS_ADDR", value = "${local.redis_host}:6379" },
      { name = "BUCKETEER_SUBSCRIBER_NON_PERSISTENT_REDIS_POOL_MAX_IDLE", value = "25" },
      { name = "BUCKETEER_SUBSCRIBER_NON_PERSISTENT_REDIS_POOL_MAX_ACTIVE", value = "25" },
      { name = "BUCKETEER_SUBSCRIBER_NON_PERSISTENT_REDIS_MODE", value = "auto" },
      { name = "BUCKETEER_SUBSCRIBER_PUBSUB_TYPE", value = "redis-stream" },
      { name = "BUCKETEER_SUBSCRIBER_PUBSUB_REDIS_SERVER_NAME", value = "non-persistent-redis" },
      { name = "BUCKETEER_SUBSCRIBER_PUBSUB_REDIS_ADDR", value = "${local.redis_host}:6379" },
      { name = "BUCKETEER_SUBSCRIBER_PUBSUB_REDIS_POOL_SIZE", value = "25" },
      { name = "BUCKETEER_SUBSCRIBER_PUBSUB_REDIS_MIN_IDLE", value = "25" },
      { name = "BUCKETEER_SUBSCRIBER_PUBSUB_REDIS_PARTITION_COUNT", value = "16" },
      { name = "BUCKETEER_SUBSCRIBER_PORT", value = "9000" },
      { name = "BUCKETEER_SUBSCRIBER_METRICS_PORT", value = "9002" },
      { name = "BUCKETEER_SUBSCRIBER_REFRESH_INTERVAL", value = "10m" },
      { name = "BUCKETEER_SUBSCRIBER_WEB_URL", value = "http://localhost:3000" },
      { name = "BUCKETEER_SUBSCRIBER_CERT", value = "/usr/local/certs/service/tls.crt" },
      { name = "BUCKETEER_SUBSCRIBER_KEY", value = "/usr/local/certs/service/tls.key" },
      { name = "BUCKETEER_SUBSCRIBER_SERVICE_TOKEN", value = "/usr/local/service-token/token" },
      { name = "BUCKETEER_SUBSCRIBER_OAUTH_PUBLIC_KEY", value = "/usr/local/oauth-key/public.pem" },
      { name = "BUCKETEER_SUBSCRIBER_NOTIFICATION_SERVICE", value = "web.${local.namespace}:9100" },
      { name = "BUCKETEER_SUBSCRIBER_ENVIRONMENT_SERVICE", value = "web.${local.namespace}:9095" },
      { name = "BUCKETEER_SUBSCRIBER_PUSH_SERVICE", value = "web.${local.namespace}:9101" },
      { name = "BUCKETEER_SUBSCRIBER_AUTO_OPS_SERVICE", value = "web.${local.namespace}:9094" },
      { name = "BUCKETEER_SUBSCRIBER_EXPERIMENT_SERVICE", value = "web.${local.namespace}:9097" },
      { name = "BUCKETEER_SUBSCRIBER_FEATURE_SERVICE", value = "web.${local.namespace}:9098" },
      { name = "BUCKETEER_SUBSCRIBER_BATCH_SERVICE", value = "nginx.${local.namespace}:443" },
      { name = "BUCKETEER_SUBSCRIBER_LOG_LEVEL", value = "info" },
      { name = "BUCKETEER_SUBSCRIBER_PROFILE", value = "false" },
      { name = "BUCKETEER_SUBSCRIBER_GCP_TRACE_ENABLED", value = "false" },
      { name = "BUCKETEER_SUBSCRIBER_SUBSCRIBER_CONFIG", value = "/usr/local/conf/subscribers.json" },
      { name = "BUCKETEER_SUBSCRIBER_ON_DEMAND_SUBSCRIBER_CONFIG", value = "/usr/local/conf/onDemandSubscribers.json" },
      { name = "BUCKETEER_SUBSCRIBER_PROCESSORS_CONFIG", value = "/usr/local/conf/processors.json" },
      { name = "BUCKETEER_SUBSCRIBER_ON_DEMAND_PROCESSORS_CONFIG", value = "/usr/local/conf/onDemandProcessors.json" },
      { name = "BUCKETEER_SUBSCRIBER_EMAIL_CONFIG_PATH", value = "/usr/local/email-config/email-config.json" }
    ]
    secrets = [
      { name = "BUCKETEER_SUBSCRIBER_MYSQL_PASS", valueFrom = aws_secretsmanager_secret.db_password.arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "subscriber"
      }
    }
  }])
}

# Task definition: Nginx (front proxy)
resource "aws_ecs_task_definition" "nginx" {
  family                   = "${local.name}-nginx"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "nginx"
    image     = "${aws_ecr_repository.nginx.repository_url}:${var.bucketeer_version}"
    essential = true
    portMappings = [
      { containerPort = 80, protocol = "tcp" },
      { containerPort = 443, protocol = "tcp" }
    ]
    environment = [
      { name = "WEB_HOST", value = "web.${local.namespace}" },
      { name = "API_HOST", value = "api.${local.namespace}" },
      { name = "BATCH_HOST", value = "batch.${local.namespace}" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "nginx"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "wget -q --spider http://localhost:80/ || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 5
      startPeriod = 120
    }
  }])
}

# Task definition: pre-migration SQL fix (run before Atlas migration)
resource "aws_ecs_task_definition" "pre_migration" {
  family                   = "${local.name}-pre-migration"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "pre-migration"
    image     = "mysql:8.0"
    essential = true
    command = [
      "sh", "-c",
      join("", [
        "TABLES='account api_key audit_log auto_ops_rule experiment experiment_result feature feature_last_used_info flag_trigger goal mau ops_count ops_progressive_rollout push segment segment_user subscription tag'; ",
        "for t in $TABLES; do ",
        "mysql -h${aws_db_instance.main.address} -u${var.db_username} -p${var.db_password} ${var.db_name} -e ",
        "\"UPDATE $t SET environment_id = COALESCE(environment_namespace, '') WHERE environment_id IS NULL; ",
        "ALTER TABLE $t MODIFY COLUMN environment_id varchar(255) NOT NULL DEFAULT '';\" 2>&1 || true; ",
        "done; ",
        "echo 'Pre-migration complete'"
      ])
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "pre-migration"
      }
    }
  }])
}

# Task definition: Migration (one-shot, run via `make migrate-aws`)
resource "aws_ecs_task_definition" "migration" {
  family                   = "${local.name}-migration"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "migration"
    image     = "ghcr.io/bucketeer-io/bucketeer-migration:${var.bucketeer_version}"
    essential = true
    command = [
      "migrate", "apply",
      "-u", "mysql://${var.db_username}:${var.db_password}@${aws_db_instance.main.address}:3306/${var.db_name}",
      "--revisions-schema", var.db_name
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "migration"
      }
    }
  }])
}

# ECS services (backend first, then nginx)
resource "aws_ecs_service" "api" {
  name            = "${local.name}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
  service_registries {
    registry_arn = aws_service_discovery_service.api.arn
  }
}

resource "aws_ecs_service" "web" {
  name            = "${local.name}-web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
  service_registries {
    registry_arn = aws_service_discovery_service.web.arn
  }
  depends_on = [aws_ecs_service.api]
}

resource "aws_ecs_service" "batch" {
  name            = "${local.name}-batch"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.batch.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
  service_registries {
    registry_arn = aws_service_discovery_service.batch.arn
  }
  depends_on = [aws_ecs_service.api]
}

resource "aws_ecs_service" "subscriber" {
  name            = "${local.name}-subscriber"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.subscriber.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
  service_registries {
    registry_arn = aws_service_discovery_service.subscriber.arn
  }
  depends_on = [aws_ecs_service.api, aws_ecs_service.web]
}

resource "aws_ecs_service" "nginx" {
  name            = "${local.name}-nginx"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.nginx.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.nginx.arn
    container_name   = "nginx"
    container_port   = 80
  }
  service_registries {
    registry_arn = aws_service_discovery_service.nginx.arn
  }
  depends_on = [aws_ecs_service.web, aws_ecs_service.batch, aws_lb_listener.http]
}

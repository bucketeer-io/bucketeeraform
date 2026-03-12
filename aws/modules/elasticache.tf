# ElastiCache Redis — free tier: cache.t3.micro, single node

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = local.name
  description          = "Redis for Bucketeer"

  node_type          = var.redis_node_type
  num_cache_clusters = var.redis_num_cache_clusters
  port               = 6379
  engine_version     = "7.0"

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = false
  transit_encryption_enabled = false

  tags = {
    Name = local.name
  }
}

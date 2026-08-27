resource "aws_security_group" "lambda_cache_sg" {
  count       = var.enable_redis_cache ? 1 : 0
  name        = "${var.project_name}-lambda-cache-sg"
  description = "Lambda egress to Redis cache"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis_sg" {
  count       = var.enable_redis_cache ? 1 : 0
  name        = "${var.project_name}-redis-sg"
  description = "Redis ingress from catalog Lambda"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_cache_sg[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  count      = var.enable_redis_cache ? 1 : 0
  name       = "${var.project_name}-redis-subnets"
  subnet_ids = [aws_subnet.private.id, aws_subnet.private_secondary.id]
}

resource "aws_elasticache_cluster" "catalog_cache" {
  count                = var.enable_redis_cache ? 1 : 0
  cluster_id           = "${var.project_name}-catalog-cache"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis[0].name
  security_group_ids   = [aws_security_group.redis_sg[0].id]
}

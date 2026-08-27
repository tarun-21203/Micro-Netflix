variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Target deployment region for the term project"
}

variable "project_name" {
  type        = string
  default     = "micro-netflix"
  description = "Prefix applied to all structural service configurations"
}

variable "enable_redis_cache" {
  type        = bool
  default     = true
  description = "Create an ElastiCache Redis node and attach the catalog Lambda to it."
}

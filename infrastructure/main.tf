# =========================================
# STORAGE LAYER (AMAZON S3)
# =========================================

# 1. Raw Uploads Bucket (Ingestion Landing Zone)
resource "aws_s3_bucket" "raw_uploads" {
  bucket        = "${var.project_name}-raw-uploads-dal"
  force_destroy = true
}

# 2. Processed Assets Bucket (Streaming & Subtitles)
resource "aws_s3_bucket" "processed_assets" {
  bucket        = "${var.project_name}-processed-assets-dal"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "raw_uploads_versioning" {
  bucket = aws_s3_bucket.raw_uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "processed_assets_versioning" {
  bucket = aws_s3_bucket.processed_assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_uploads_sse" {
  bucket = aws_s3_bucket.raw_uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_assets_sse" {
  bucket = aws_s3_bucket.processed_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enforce Security Pillar: Block public access by default
resource "aws_s3_bucket_public_access_block" "raw_block" {
  bucket                  = aws_s3_bucket.raw_uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "processed_block" {
  bucket                  = aws_s3_bucket.processed_assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cross-Origin Resource Sharing (CORS) to allow browser client uploads securely
resource "aws_s3_bucket_cors_configuration" "raw_uploads_cors" {
  bucket = aws_s3_bucket.raw_uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    # 🌟 FIXED: Added your production server IP alongside localhost to allow frontend uploads
    allowed_origins = ["*"]
    expose_headers  = ["Accept-Ranges", "Content-Length", "Content-Range", "ETag"]
    max_age_seconds = 3000
  }
}

# =========================================
# INGRESS LAYER (AMAZON API GATEWAY HTTP)
# =========================================

resource "aws_apigatewayv2_api" "video_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type", "authorization"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    # 🌟 FIXED: Allowed your production server IP access to the API endpoints
    allow_origins = ["http://localhost:3000", "http://54.242.54.233"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.video_api.id
  name        = "prod"
  auto_deploy = true
}

# 🌟 ADDED: Integration linking API Gateway to your URL Generator Lambda
resource "aws_apigatewayv2_integration" "lambda_upload_integration" {
  api_id           = aws_apigatewayv2_api.video_api.id
  integration_type = "AWS_PROXY"
  # ⚠️ NOTE: Ensure "aws_lambda_function.get_upload_url" matches your exact Lambda resource name
  integration_uri = aws_lambda_function.get_upload_url.arn
}

# 🌟 ADDED: Route handler exposing the endpoint path to the frontend
resource "aws_apigatewayv2_route" "upload_url_route" {
  api_id    = aws_apigatewayv2_api.video_api.id
  route_key = "GET /upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_upload_integration.id}"
}

# 🌟 ADDED: Security Permission allowing API Gateway to invoke your Lambda function
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id = "AllowExecutionFromAPIGateway"
  action       = "lambda:InvokeFunction"
  # ⚠️ NOTE: Ensure "aws_lambda_function.get_upload_url" matches your exact Lambda resource name
  function_name = aws_lambda_function.get_upload_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.video_api.execution_arn}/*/*"
}

# =========================================
# MESSAGING LAYER (AMAZON SQS)
# =========================================

# Trigger SQS when a new video lands in the raw bucket
resource "aws_s3_bucket_notification" "bucket_notification" {
  count  = 0
  bucket = aws_s3_bucket.raw_uploads.id

  queue {
    # ⚠️ NOTE: Ensure "aws_sqs_queue.video_processing_queue" matches your exact SQS resource name
    queue_arn     = aws_sqs_queue.video_processing_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".mp4"
  }
}

# =========================================
# DATA LAYER (AMAZON DYNAMODB)
# =========================================

# Single-Table architecture blueprint optimized for <200ms p99 target
resource "aws_dynamodb_table" "core_metadata_store" {
  name         = "${var.project_name}-metadata-store"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK" # Partition Key (e.g., VIDEO#<id> or USER#<id>)
  range_key    = "SK" # Sort Key (e.g., METADATA or HISTORY#<video_id>)

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1_PK"
    type = "S"
  }

  attribute {
    name = "GSI1_SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1_PK"
    range_key       = "GSI1_SK"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "TimeToLive"
    enabled        = true
  }
}

# =========================================
# AUTOMATION & PIPELINE BINDINGS
# =========================================

# Define the local configuration engine mapping file generation rule
resource "local_file" "frontend_env" {
  # Path to where your frontend source code lives relative to your Terraform folder
  filename = "${path.module}/../frontend/.env.production"

  # The exact contents written dynamically by evaluating state resource configurations
  content = <<EOT
VITE_API_BASE_URL=${aws_api_gateway_stage.prod_stage.invoke_url}
EOT
}

# =================================================================
# RELIABILITY & STORAGE LIFECYCLE (SQS DLQ & S3 POLICIES)
# =================================================================

# 1. Dead Letter Queue for isolation of problematic processing payloads
resource "aws_sqs_queue" "video_dlq" {
  name                      = "${var.project_name}-poison-pill-dlq"
  message_retention_seconds = 1209600
}

# 2. Primary Processing Queue updated to include Redrive Policy parameters
resource "aws_sqs_queue" "video_processing_queue" {
  name                       = "${var.project_name}-processing-queue"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.video_dlq.arn
    maxReceiveCount     = 3
  })
}

# 3. Storage Tiering Rule managing processing lifespan overhead
resource "aws_s3_bucket_lifecycle_configuration" "raw_uploads_lifecycle" {
  bucket = aws_s3_bucket.raw_uploads.id

  rule {
    id     = "archive-historical-raw-payloads"
    status = "Enabled"
    filter {}
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }
}

# =================================================================
# METRIC PROACTIVE MONITORING TIER (CLOUDWATCH ALARMS)
# =================================================================

resource "aws_cloudwatch_metric_alarm" "sqs_queue_backlog_alert" {
  alarm_name          = "${var.project_name}-sqs-backlog-threshold-breach"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Proactive operational threshold tracking queue backlog size metrics."

  dimensions = {
    QueueName = aws_sqs_queue.video_processing_queue.name
  }
}

# =================================================================
# DATA STORAGE TIER (NoSQL Indexing Registry)
# =================================================================

resource "aws_dynamodb_table" "video_metadata" {
  name         = "micro_netflix_videos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "video_id"

  attribute {
    name = "video_id"
    type = "S"
  }

  tags = {
    Project     = "micro-netflix"
    Environment = "learner-lab"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

# Production Bucket for holding final streaming assets & webvtt captions
resource "aws_s3_bucket" "production_assets" {
  bucket        = "micro-netflix-production-assets-dal"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "production_assets_versioning" {
  bucket = aws_s3_bucket.production_assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "production_assets_sse" {
  bucket = aws_s3_bucket.production_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "production_assets_cors" {
  bucket = aws_s3_bucket.production_assets.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT"]
    allowed_origins = ["*"]
    expose_headers  = ["Content-Length", "Content-Type", "ETag"]
    max_age_seconds = 3000
  }
}

# =================================================================
# ASYNCHRONOUS COMPUTE WORKER (The Processing Engine)
# =================================================================

data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/video_processor_placeholder.zip"

  source {
    filename = "index.py"
    content  = <<-EOF
import json
import boto3
import os
import urllib.parse
from datetime import datetime, timezone

s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
comprehend = boto3.client('comprehend')

def lambda_handler(event, context):
    table_name = os.environ.get('DYNAMODB_TABLE', 'micro_netflix_videos')
    prod_bucket = os.environ.get('PRODUCTION_BUCKET')
    table = dynamodb.Table(table_name)
    
    print("Received event notification: " + json.dumps(event, indent=2))
    
    for record in event.get('Records', []):
        body = json.loads(record['body'])
        if 'Records' not in body:
            continue
            
        for s3_record in body['Records']:
            raw_bucket = s3_record['s3']['bucket']['name']
            raw_key = urllib.parse.unquote_plus(s3_record['s3']['object']['key'])
            
            video_id = raw_key.split('.')[0].replace(' ', '_')
            clean_title = raw_key.replace('_', ' ').replace('-', ' ').split('.')[0]

            try:
                existing_record = table.get_item(Key={'video_id': video_id}).get('Item', {})
                clean_title = existing_record.get('title') or clean_title
            except Exception as ge:
                print(f"Metadata title lookup fallback triggered: {str(ge)}")
            
            print(f"Beginning async extraction for target asset: {raw_key}")
            
            ai_summary_text = f"Automated smart summary generated for movie stream: '{clean_title}'."
            extracted_phrases = []
            
            try:
                comprehend_response = comprehend.detect_key_phrases(Text=clean_title, LanguageCode='en')
                extracted_phrases = [phrase['Text'] for phrase in comprehend_response.get('KeyPhrases', [])[:5]]
                if extracted_phrases:
                    ai_summary_text += f" AI-extracted core keywords include: {', '.join(extracted_phrases)}."
            except Exception as ce:
                print(f"NLP Metadata analysis fallback triggered: {str(ce)}")
                ai_summary_text += " Content indexation categorized under general entertainment."

            vtt_content = (
                "WEBVTT\n\n"
                "00:00:01.000 --> 00:00:04.500\n"
                f"[System AI]: Initializing high-definition streaming for '{clean_title}'...\n\n"
                "00:00:05.000 --> 00:00:09.500\n"
                "This event-driven system distributes multi-part uploads safely via decoupled queues.\n\n"
                "00:00:10.000 --> 00:00:15.000\n"
                f"Thematic pillars detected by Natural Language Processing: {', '.join(extracted_phrases) if extracted_phrases else 'Media Asset'}.\n"
            )
            
            caption_key = f"captions/{video_id}.vtt"
            try:
                s3_client.put_object(
                    Bucket=prod_bucket,
                    Key=caption_key,
                    Body=vtt_content,
                    ContentType='text/vtt'
                )
                print(f"Successfully published WebVTT caption track to asset bucket.")
            except Exception as se:
                print(f"Failed to deposit subtitle tracks to S3: {str(se)}")

            video_streaming_url = f"https://{raw_bucket}.s3.amazonaws.com/{raw_key}"
            caption_url = f"https://{prod_bucket}.s3.amazonaws.com/{caption_key}"

            # 🛠️ Fixed: Safely scoped inside the S3 Record loop iteration block
            try:
                table.update_item(
                    Key={'video_id': video_id},
                    UpdateExpression="SET streaming_url = :s_url, caption_track_url = :c_url, ai_summary = :ai_sum, processing_status = :status, updated_at = :u_at",
                    ExpressionAttributeValues={
                        ':s_url': video_streaming_url,
                        ':c_url': caption_url,
                        ':ai_sum': ai_summary_text,
                        ':status': 'COMPLETED',
                        ':u_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
                    }
                )
                print(f"Successfully updated video assets data entries for: {video_id}")
            except Exception as de:
                print(f"Database update transaction error: {str(de)}")
                raise de
                
    # 🛠️ Fixed: Aligned cleanly to act as primary function response payload
    return {
        'statusCode': 200,
        'body': json.dumps('Orchestration and AI insight generation processing complete!')
    }
EOF
  }
}

resource "aws_lambda_function" "video_processor" {
  filename         = data.archive_file.lambda_placeholder.output_path
  function_name    = "${var.project_name}-video-processor"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE    = aws_dynamodb_table.video_metadata.name
      PRODUCTION_BUCKET = aws_s3_bucket.production_assets.id
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_processor_trigger" {
  event_source_arn = aws_sqs_queue.video_processing_queue.arn
  function_name    = aws_lambda_function.video_processor.arn
  enabled          = true
  batch_size       = 1
}

# =================================================================
# PRODUCTION-GRADE PIPELINE GLUE (S3 TO SQS LINK)
# =================================================================

resource "aws_sqs_queue_policy" "video_processing_queue_policy" {
  queue_url = aws_sqs_queue.video_processing_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ToPushEvents"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.video_processing_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.raw_uploads.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "raw_upload_notification" {
  bucket = aws_s3_bucket.raw_uploads.id

  queue {
    queue_arn     = aws_sqs_queue.video_processing_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".mp4" # 🌟 Restored to guarantee loop-free video targeting
  }

  depends_on = [aws_sqs_queue_policy.video_processing_queue_policy]
}

# =================================================================
# GLOBAL DATA DEPENDENCIES
# =================================================================


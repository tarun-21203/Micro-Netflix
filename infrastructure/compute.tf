# =================================================================
# CODE PACKAGING & IAM CONTEXT
# =================================================================

data "archive_file" "api_handlers_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/api_handlers"
  output_path = "${path.module}/api_handlers.zip"
}

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# =================================================================
# COMPUTE TIER: API ENDPOINT HANDLERS
# =================================================================

# Endpoint 1: Presigned S3 URL Generator
resource "aws_lambda_function" "get_upload_url" {
  filename         = data.archive_file.api_handlers_zip.output_path
  function_name    = "${var.project_name}-get-upload-url"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "get_upload_url.lambda_handler"
  source_code_hash = data.archive_file.api_handlers_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 10

  environment {
    variables = {
      RAW_BUCKET_NAME        = aws_s3_bucket.raw_uploads.id
      THUMBNAILS_BUCKET_NAME = aws_s3_bucket.production_assets.id
      DYNAMODB_TABLE         = aws_dynamodb_table.video_metadata.name
    }
  }
}

# Packaged source configuration for the catalog read layer
data "archive_file" "lambda_reader" {
  type        = "zip"
  output_path = "${path.module}/video_reader.zip"

  source {
    filename = "index.py"
    content  = <<-EOF
import json
import boto3
import os
import base64
import hashlib
import socket
from urllib.parse import urlparse, unquote

dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')

def redis_request(host, port, parts, timeout=0.25):
    if not host:
        return None
    payload = f"*{len(parts)}\r\n".encode('utf-8')
    for part in parts:
        value = str(part).encode('utf-8')
        payload += f"$${len(value)}\r\n".encode('utf-8') + value + b"\r\n"
    with socket.create_connection((host, int(port)), timeout=timeout) as conn:
        conn.sendall(payload)
        data = conn.recv(1048576)
    if not data or data.startswith(b"$-1"):
        return None
    if data.startswith(b"+") or data.startswith(b":"):
        return data.split(b"\r\n", 1)[0][1:].decode('utf-8')
    if data.startswith(b"$"):
        return data.split(b"\r\n", 2)[1]
    return None

def cache_get(key):
    try:
        value = redis_request(os.environ.get('REDIS_HOST', ''), os.environ.get('REDIS_PORT', '6379'), ['GET', key])
        if isinstance(value, bytes):
            return value.decode('utf-8')
        return value
    except Exception as cache_error:
        print(f"Redis read skipped: {cache_error}")
        return None

def cache_set(key, value):
    try:
        redis_request(
            os.environ.get('REDIS_HOST', ''),
            os.environ.get('REDIS_PORT', '6379'),
            ['SETEX', key, os.environ.get('CATALOG_CACHE_TTL_SECONDS', '60'), value],
            timeout=0.5
        )
    except Exception as cache_error:
        print(f"Redis write skipped: {cache_error}")

def encode_token(key):
    if not key:
        return None
    return base64.urlsafe_b64encode(json.dumps(key).encode('utf-8')).decode('utf-8')

def decode_token(token):
    if not token:
        return None
    return json.loads(base64.urlsafe_b64decode(token.encode('utf-8')).decode('utf-8'))

def presign(bucket, key, expires=3600):
    if not bucket or not key:
        return ''
    return s3_client.generate_presigned_url(
        'get_object',
        Params={'Bucket': bucket, 'Key': key},
        ExpiresIn=expires
    )

def key_from_url(value):
    if not value:
        return ''
    parsed = urlparse(value)
    return unquote(parsed.path.lstrip('/'))

def cdn_url(domain, key):
    if not domain or not key:
        return ''
    return f"https://{domain}/{key}"

def normalize_item(item, raw_bucket, asset_bucket):
    video_id = item.get('video_id', '')
    raw_key = item.get('raw_source_file') or key_from_url(item.get('streaming_url', ''))
    caption_key = item.get('caption_key') or key_from_url(item.get('caption_track_url', '')) or (f"captions/{video_id}.vtt" if video_id else '')
    thumbnail_key = item.get('thumbnail_key') or (f"thumbnails/{video_id}.jpg" if video_id else '')
    raw_cdn_domain = os.environ.get('RAW_CDN_DOMAIN', '')
    asset_cdn_domain = os.environ.get('ASSET_CDN_DOMAIN', '')

    item['streaming_url'] = cdn_url(raw_cdn_domain, raw_key) or (presign(raw_bucket, raw_key) if raw_key else item.get('streaming_url', ''))
    item['caption_track_url'] = cdn_url(asset_cdn_domain, caption_key) or (presign(asset_bucket, caption_key) if caption_key else item.get('caption_track_url', ''))
    item['thumbnail_url'] = cdn_url(asset_cdn_domain, thumbnail_key) or (presign(asset_bucket, thumbnail_key) if thumbnail_key else '')
    item['title'] = item.get('title') or item.get('original_file_name') or video_id or 'Untitled video'
    item['ai_summary'] = item.get('ai_summary') or 'AI summary is still being prepared.'
    item['processing_status'] = item.get('processing_status') or 'PROCESSING'
    return item

def lambda_handler(event, context):
    table_name = os.environ.get('DYNAMODB_TABLE', 'micro_netflix_videos')
    raw_bucket = os.environ.get('RAW_BUCKET_NAME')
    asset_bucket = os.environ.get('PRODUCTION_BUCKET')
    table = dynamodb.Table(table_name)
    
    try:
        params = event.get('queryStringParameters') or {}
        limit = min(max(int(params.get('limit', 12)), 1), 24)
        search = (params.get('search') or '').strip().lower()
        exclusive_start_key = decode_token(params.get('nextToken'))
        cache_key = "catalog:" + hashlib.sha256(json.dumps({
            'limit': limit,
            'search': search,
            'nextToken': params.get('nextToken') or ''
        }, sort_keys=True).encode('utf-8')).hexdigest()
        cached_payload = cache_get(cache_key)

        if cached_payload:
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Authorization,Content-Type',
                    'Access-Control-Allow-Methods': 'GET,OPTIONS',
                    'X-Cache': 'HIT'
                },
                'body': cached_payload
            }

        if search:
            items = []
            last_key = exclusive_start_key
            pages_scanned = 0

            while len(items) < limit and pages_scanned < 10:
                scan_kwargs = {'Limit': limit}
                if last_key:
                    scan_kwargs['ExclusiveStartKey'] = last_key

                response = table.scan(**scan_kwargs)
                pages_scanned += 1
                last_key = response.get('LastEvaluatedKey')

                for item in response.get('Items', []):
                    searchable = ' '.join([
                        str(item.get('title', '')),
                        str(item.get('original_file_name', '')),
                        str(item.get('ai_summary', '')),
                        str(item.get('processing_status', ''))
                    ]).lower()
                    if search in searchable:
                        items.append(item)
                        if len(items) == limit:
                            break

                if not last_key:
                    break
        else:
            scan_kwargs = {'Limit': limit}
            if exclusive_start_key:
                scan_kwargs['ExclusiveStartKey'] = exclusive_start_key

            response = table.scan(**scan_kwargs)
            items = response.get('Items', [])
            last_key = response.get('LastEvaluatedKey')

        items = [normalize_item(item, raw_bucket, asset_bucket) for item in items]
        payload = json.dumps({
            'videos': items,
            'nextToken': encode_token(last_key)
        })
        cache_set(cache_key, payload)
        
        # ✅ Proxy Integration JSON response wrapper
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Authorization,Content-Type',
                'Access-Control-Allow-Methods': 'GET,OPTIONS',
                'X-Cache': 'MISS'
            },
            'body': payload
        }
    except Exception as e:
        print(str(e))
        return {
            'statusCode': 500,
            'headers': { 
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*' 
            },
            'body': json.dumps({'error': 'Failed to retrieve video database registry'})
        }
    EOF
  }
}

# Endpoint 2: Database Catalog Reader
resource "aws_lambda_function" "get_catalog" {
  filename         = data.archive_file.lambda_reader.output_path
  function_name    = "${var.project_name}-get-catalog"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_reader.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      DYNAMODB_TABLE            = aws_dynamodb_table.video_metadata.name
      RAW_BUCKET_NAME           = aws_s3_bucket.raw_uploads.id
      PRODUCTION_BUCKET         = aws_s3_bucket.production_assets.id
      RAW_CDN_DOMAIN            = ""
      ASSET_CDN_DOMAIN          = ""
      REDIS_HOST                = var.enable_redis_cache ? aws_elasticache_cluster.catalog_cache[0].cache_nodes[0].address : ""
      REDIS_PORT                = "6379"
      CATALOG_CACHE_TTL_SECONDS = "60"
    }
  }

  dynamic "vpc_config" {
    for_each = var.enable_redis_cache ? [1] : []
    content {
      subnet_ids         = [aws_subnet.private.id, aws_subnet.private_secondary.id]
      security_group_ids = [aws_security_group.lambda_cache_sg[0].id]
    }
  }
}

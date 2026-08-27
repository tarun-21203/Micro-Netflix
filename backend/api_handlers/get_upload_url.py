import json
import boto3
import os
import uuid
from datetime import datetime, timezone

s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    bucket_name = os.environ.get('RAW_BUCKET_NAME')
    thumbnails_bucket = os.environ.get('THUMBNAILS_BUCKET_NAME')
    table_name = os.environ.get('DYNAMODB_TABLE')
    table = dynamodb.Table(table_name)
    
    try:
        if event.get('httpMethod') == 'OPTIONS':
            return build_response(200, {})

        # 1. Parse incoming metadata from the Frontend request body.
        # Query string fallback keeps older local frontend builds from failing.
        body = json.loads(event.get('body') or '{}')
        query = event.get('queryStringParameters') or {}
        filename = body.get('filename') or query.get('filename')
        content_type = body.get('contentType') or query.get('contentType') or 'video/mp4'
        user_title = (body.get('title') or query.get('title') or '').strip()
        
        if not filename:
            return build_response(400, {'error': 'Missing required parameter: filename'})
            
        # 2. Smart Defaulting: If the title is blank, use the filename without extension
        if not user_title:
            user_title = filename.rsplit('.', 1)[0].replace('_', ' ').replace('-', ' ')
            
        # 3. Generate a distinct immutable primary key tracking reference
        # This keeps S3 object keys unique even if two users upload "movie.mp4"
        file_extension = filename.split('.')[-1] if '.' in filename else 'mp4'
        video_id = str(uuid.uuid4())
        unique_s3_key = f"{video_id}.{file_extension}"
        thumbnail_key = f"thumbnails/{video_id}.jpg"
        
        # 4. Pre-register the video metadata as PENDING in DynamoDB
        table.put_item(
            Item={
                'video_id': video_id,
                'title': user_title,
                'original_file_name': filename,
                'raw_source_file': unique_s3_key,
                'thumbnail_key': thumbnail_key,
                'caption_key': f"captions/{video_id}.vtt",
                'ai_summary': 'Upload received. AI processing will start after the video reaches S3.',
                'processing_status': 'PENDING',
                'uploaded_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
            }
        )
        
        # 5. Generate the restricted S3 Presigned Upload URL
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': bucket_name,
                'Key': unique_s3_key,
                'ContentType': content_type
            },
            ExpiresIn=300 # URL remains active for 5 minutes
        )

        thumbnail_upload_url = None
        if thumbnails_bucket:
            thumbnail_upload_url = s3_client.generate_presigned_url(
                'put_object',
                Params={
                    'Bucket': thumbnails_bucket,
                    'Key': thumbnail_key,
                    'ContentType': 'image/jpeg'
                },
                ExpiresIn=300
            )
        
        return build_response(
            200,
            {
                'upload_url': presigned_url,
                'video_id': video_id,
                's3_key': unique_s3_key,
                'thumbnail_upload_url': thumbnail_upload_url,
                'thumbnail_key': thumbnail_key,
                'title': user_title
            }
        )
        
    except Exception as e:
        print(f"Error handling pre-registration sequence: {str(e)}")
        return build_response(500, {'error': 'Failed to initialize the upload registration pipeline'})


def build_response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Authorization,Content-Type',
            'Access-Control-Allow-Methods': 'POST,OPTIONS'
        },
        'body': json.dumps(body)
    }

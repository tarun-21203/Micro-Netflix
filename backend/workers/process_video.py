import json
import boto3
import os

transcribe = boto3.client('transcribe')
PROCESSED_BUCKET = os.environ['PROCESSED_BUCKET_NAME']

def lambda_handler(event, context):
    for record in event['Records']:
        # Parse the SQS message containing the S3 event
        body = json.loads(record['body'])
        
        if 'Records' in body:
            for s3_event in body['Records']:
                source_bucket = s3_event['s3']['bucket']['name']
                object_key = s3_event['s3']['object']['key']
                
                job_name = f"Transcribe_{object_key.replace('.mp4', '')}"
                job_uri = f"s3://{source_bucket}/{object_key}"
                
                print(f"Starting AI Transcription for {job_uri}")
                
                # Start the AI transcription job
                transcribe.start_transcription_job(
                    TranscriptionJobName=job_name,
                    Media={'MediaFileUri': job_uri},
                    MediaFormat='mp4',
                    LanguageCode='en-US',
                    OutputBucketName=PROCESSED_BUCKET,
                    Subtitles={'Formats': ['vtt']} # Generates a subtitle file
                )
    
    return {"statusCode": 200, "body": "Processing triggered successfully"}
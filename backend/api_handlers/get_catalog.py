import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ['TABLE_NAME']
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    try:
        # Fetching all items where Sort Key is 'METADATA'
        response = table.scan(
            FilterExpression="SK = :sk_val",
            ExpressionAttributeValues={":sk_val": "METADATA"}
        )
        
        return {
            "statusCode": 200,
            "headers": {"Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"videos": response.get('Items', [])})
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
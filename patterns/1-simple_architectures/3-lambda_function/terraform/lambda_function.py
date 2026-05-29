# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import json

def lambda_handler(event, context):
    # Extract the source IP from the request context
    request_context = event.get('requestContext', {})
    source_ip = request_context.get('http', {}).get('sourceIp', 'Unknown')
    
    # Create response with message and request IP
    response_body = {
        'message': 'Hello from Lambda Function!!',
        'request_ip': source_ip
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps(response_body)
    }
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route('/', methods=['GET'])
def hello():
    # Get the request IP address
    # Check X-Forwarded-For header first (VPC Lattice may use this)
    request_ip = request.headers.get('X-Forwarded-For', request.remote_addr)

    # Create response with message and request IP
    response = {
        "message": "Hello from ECS Fargate!!",
        "request_ip": request_ip
    }

    return jsonify(response), 200

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Send a SigV4-signed request to a VPC Lattice service (single Region).
# Signing name is "vpc-lattice-svcs"; VPC Lattice does not support payload
# signing, so the x-amz-content-sha256 header is set to UNSIGNED-PAYLOAD.
# Adapted from the AWS VPC Lattice documentation (SigV4 authenticated requests).
#
# Requires: pip install botocore awscrt requests
import botocore.session
import requests
from botocore import crt
from botocore.awsrequest import AWSRequest

REGION = "eu-west-1"
ENDPOINT = "https://<service-domain-name>"

def main():
    session = botocore.session.Session()
    # Credentials are resolved from the environment / instance role (IMDS) / profile.
    signer = crt.auth.CrtSigV4Auth(session.get_credentials(), "vpc-lattice-svcs", REGION)

    headers = {
        "Content-Type": "application/json",
        "x-amz-content-sha256": "UNSIGNED-PAYLOAD",
    }
    request = AWSRequest(method="GET", url=ENDPOINT, headers=headers)
    request.context["payload_signing_enabled"] = False
    signer.add_auth(request)

    prepped = request.prepare()
    response = requests.get(prepped.url, headers=prepped.headers)
    print(response.status_code, response.text)


if __name__ == "__main__":
    main()

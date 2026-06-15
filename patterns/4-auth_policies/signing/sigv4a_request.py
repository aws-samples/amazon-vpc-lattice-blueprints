# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Send a SigV4A-signed request to a VPC Lattice service. SigV4A is the
# multi-Region variant of SigV4: the signature is computed over a Region SET
# ("*" = all Regions) instead of a single Region, which is useful when the same
# signed request may be served from more than one Region.
# Signing name is "vpc-lattice-svcs"; payload signing is not supported, so the
# x-amz-content-sha256 header is set to UNSIGNED-PAYLOAD.
# Adapted from the AWS VPC Lattice documentation (SigV4 authenticated requests).
#
# Requires: pip install botocore awscrt requests
import botocore.session
import requests
from botocore import crt
from botocore.awsrequest import AWSRequest

REGION_SET = "*"
ENDPOINT = "https://<service-domain-name>"

def main():
    session = botocore.session.Session()
    # CrtSigV4AsymAuth performs SigV4A signing over the Region set.
    signer = crt.auth.CrtSigV4AsymAuth(session.get_credentials(), "vpc-lattice-svcs", REGION_SET)

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

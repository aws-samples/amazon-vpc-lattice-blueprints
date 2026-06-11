.PHONY: deploy deploy-sn deploy-consumer deploy-provider undeploy

deploy: deploy-sn deploy-consumer deploy-provider

deploy-sn:
	aws cloudformation deploy --stack-name vpclattice-instance-target-networking --template-file networking.yaml --no-fail-on-empty-changeset --region eu-west-1

deploy-consumer: SERVICENETWORK = $(shell aws cloudformation describe-stacks --stack-name "vpclattice-instance-target-networking" --query 'Stacks[0].Outputs[?OutputKey == `VpcLatticeServiceNetworkId`].OutputValue' --output text --region eu-west-1 )
deploy-consumer:
	aws cloudformation deploy --stack-name vpclattice-instance-consumer --template-file consumer.yaml --parameter-overrides ServiceNetworkId="$(SERVICENETWORK)" --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset --region eu-west-1

deploy-provider: SERVICENETWORK = $(shell aws cloudformation describe-stacks --stack-name "vpclattice-instance-target-networking" --query 'Stacks[0].Outputs[?OutputKey == `VpcLatticeServiceNetworkId`].OutputValue' --output text --region eu-west-1 )
deploy-provider: CONSUMERVPC = $(shell aws cloudformation describe-stacks --stack-name "vpclattice-instance-consumer" --query 'Stacks[0].Outputs[?OutputKey == `ConsumerVpcId`].OutputValue' --output text --region eu-west-1 )
deploy-provider:
	aws cloudformation deploy --stack-name vpclattice-instance-provider --template-file provider.yaml \
        --parameter-overrides \
        ServiceNetworkId="$(SERVICENETWORK)" \
        ConsumerVpcId="$(CONSUMERVPC)" \
        Service2CustomDomainName="$(CUSTOM_DOMAIN_NAME)" \
        Service2CertificateArn="$(CERTIFICATE_ARN)" \
        HostedZoneName="$(HOSTED_ZONE_NAME)" \
        --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset --region eu-west-1

undeploy:
	aws cloudformation delete-stack --stack-name vpclattice-instance-consumer --region eu-west-1
	aws cloudformation delete-stack --stack-name vpclattice-instance-provider --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-instance-consumer --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-instance-provider --region eu-west-1
	aws cloudformation delete-stack --stack-name vpclattice-instance-target-networking --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-instance-target-networking --region eu-west-1

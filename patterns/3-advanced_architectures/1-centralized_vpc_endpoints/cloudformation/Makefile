.PHONY: deploy deploy-endpoints deploy-consumer undeploy

deploy: deploy-endpoints deploy-consumer

deploy-endpoints:
	aws cloudformation deploy --stack-name vpclattice-advanced-endpoints-provider --template-file vpc_endpoints.yaml --no-fail-on-empty-changeset --region eu-west-1

deploy-consumer: SSM = $(shell aws cloudformation describe-stacks --stack-name "vpclattice-advanced-endpoints-provider" --query 'Stacks[0].Outputs[?OutputKey == `ssmResourceConfiguration`].OutputValue' --output text --region eu-west-1 )
deploy-consumer: SSMMESSAGES = $(shell aws cloudformation describe-stacks --stack-name "vpclattice-advanced-endpoints-provider" --query 'Stacks[0].Outputs[?OutputKey == `ssmmessagesResourceConfiguration`].OutputValue' --output text --region eu-west-1 )
deploy-consumer: EC2MESSAGES = $(shell aws cloudformation describe-stacks --stack-name "vpclattice-advanced-endpoints-provider" --query 'Stacks[0].Outputs[?OutputKey == `ec2messagesResourceConfiguration`].OutputValue' --output text --region eu-west-1 )
deploy-consumer: STS = $(shell aws cloudformation describe-stacks --stack-name "vpclattice-advanced-endpoints-provider" --query 'Stacks[0].Outputs[?OutputKey == `stsResourceConfiguration`].OutputValue' --output text --region eu-west-1 )
deploy-consumer:
	aws cloudformation deploy --stack-name vpclattice-advanced-endpoints-consumer --template-file consumer.yaml --parameter-overrides ssmResourceConfiguration="$(SSM)" ssmmessagesResourceConfiguration="$(SSMMESSAGES)" ec2messagesResourceConfiguration="$(EC2MESSAGES)" stsResourceConfiguration="$(STS)" --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --region eu-west-1

undeploy:
	aws cloudformation delete-stack --stack-name vpclattice-advanced-endpoints-consumer --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-advanced-endpoints-consumer --region eu-west-1
	aws cloudformation delete-stack --stack-name vpclattice-advanced-endpoints-provider --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-advanced-endpoints-provider --region eu-west-1

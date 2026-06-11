.PHONY: deploy deploy-sn deploy-consumer-provider undeploy

deploy: deploy-sn deploy-consumer-provider

deploy-sn:
	aws cloudformation deploy --stack-name vpclattice-lambda-networking --template-file networking.yaml --no-fail-on-empty-changeset --region eu-west-1

deploy-consumer-provider: SERVICENETWORK = $(shell aws cloudformation describe-stacks --stack-name "vpclattice-lambda-networking" --query 'Stacks[0].Outputs[?OutputKey == `VpcLatticeServiceNetworkId`].OutputValue' --output text --region eu-west-1 )
deploy-consumer-provider:
	aws cloudformation deploy --stack-name vpclattice-lambda-consumer --template-file consumer.yaml --parameter-overrides ServiceNetworkId="$(SERVICENETWORK)" --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset --region eu-west-1
	aws cloudformation deploy --stack-name vpclattice-lambda-provider --template-file provider.yaml --parameter-overrides ServiceNetworkId="$(SERVICENETWORK)" --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --region eu-west-1

undeploy:
	aws cloudformation delete-stack --stack-name vpclattice-lambda-consumer --region eu-west-1
	aws cloudformation delete-stack --stack-name vpclattice-lambda-provider --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-lambda-consumer --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-lambda-provider --region eu-west-1
	aws cloudformation delete-stack --stack-name vpclattice-lambda-networking --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-lambda-networking --region eu-west-1

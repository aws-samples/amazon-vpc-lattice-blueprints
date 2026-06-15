.PHONY: deploy deploy-sn deploy-consumer deploy-provider undeploy

deploy: deploy-sn deploy-consumer deploy-provider

deploy-sn:
	aws cloudformation deploy --stack-name vpclattice-rds-networking --template-file networking.yaml --no-fail-on-empty-changeset --region eu-west-1

deploy-consumer: SERVICENETWORK = $(shell aws cloudformation describe-stacks --stack-name "vpclattice-rds-networking" --query 'Stacks[0].Outputs[?OutputKey == `VpcLatticeServiceNetworkId`].OutputValue' --output text --region eu-west-1 )
deploy-consumer:
	aws cloudformation deploy --stack-name vpclattice-rds-consumer --template-file consumer.yaml --parameter-overrides ServiceNetworkId="$(SERVICENETWORK)" --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset --region eu-west-1

deploy-provider: SERVICENETWORK = $(shell aws cloudformation describe-stacks --stack-name "vpclattice-rds-networking" --query 'Stacks[0].Outputs[?OutputKey == `VpcLatticeServiceNetworkId`].OutputValue' --output text --region eu-west-1 )
deploy-provider:
	aws cloudformation deploy --stack-name vpclattice-rds-provider --template-file provider.yaml --parameter-overrides ServiceNetworkId="$(SERVICENETWORK)" --no-fail-on-empty-changeset --region eu-west-1

undeploy:
	aws cloudformation delete-stack --stack-name vpclattice-rds-consumer --region eu-west-1
	aws cloudformation delete-stack --stack-name vpclattice-rds-provider --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-rds-consumer --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-rds-provider --region eu-west-1
	aws cloudformation delete-stack --stack-name vpclattice-rds-networking --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-rds-networking --region eu-west-1

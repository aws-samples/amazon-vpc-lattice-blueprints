.PHONY: deploy deploy-endpoints deploy-consumer undeploy

deploy: deploy-endpoints deploy-consumer

deploy-endpoints:
	aws cloudformation deploy --stack-name vpclattice-advanced-endpoints-provider --template-file vpc_endpoints.yaml --no-fail-on-empty-changeset --region eu-west-1

deploy-consumer: RESOURCE_CONFIG_GROUP = $(shell aws cloudformation describe-stacks --stack-name "vpclattice-advanced-endpoints-provider" --query 'Stacks[0].Outputs[?OutputKey == `ResourceConfigurationGroup`].OutputValue' --output text --region eu-west-1 )
deploy-consumer:
	aws cloudformation deploy --stack-name vpclattice-advanced-endpoints-consumer --template-file consumer.yaml --parameter-overrides ResourceConfigurationGroup="$(RESOURCE_CONFIG_GROUP)" --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --region eu-west-1

undeploy:
	aws cloudformation delete-stack --stack-name vpclattice-advanced-endpoints-consumer --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-advanced-endpoints-consumer --region eu-west-1
	aws cloudformation delete-stack --stack-name vpclattice-advanced-endpoints-provider --region eu-west-1
	aws cloudformation wait stack-delete-complete --stack-name vpclattice-advanced-endpoints-provider --region eu-west-1

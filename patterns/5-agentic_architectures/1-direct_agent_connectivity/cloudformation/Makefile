.PHONY: deploy check-domain deploy-common build-push deploy-central deploy-backends deploy-registry deploy-consumer deploy-dns submit-records chat invoke-ecs invoke-runtime undeploy

REGION ?= eu-west-1
STACK_PREFIX = vpclattice-agentic-direct
IDENTIFIER ?= agentic-direct
MODEL_ID ?= eu.anthropic.claude-haiku-5-5
# Required: domain of the services' custom domain names, and an ACM certificate that covers *.<HOSTED_ZONE_NAME>
HOSTED_ZONE_NAME ?=
CERTIFICATE_ARN ?=
PAYLOAD ?= {"action": "whoami"}
AGENT ?= ecs
APPLICATIONS = ../../applications
BUILD_DIR = .build
comma = ,
space = $(empty) $(empty)

# Read a stack output: $(call output,<stack-suffix>,<OutputKey>)
output = $(shell aws cloudformation describe-stacks --stack-name $(STACK_PREFIX)-$(1) --query 'Stacks[0].Outputs[?OutputKey == `$(2)`].OutputValue' --output text --region $(REGION))
# DNS entry VPC Lattice created for a service on the service network endpoint: $(call endpoint_dns,<endpoint-id>,<service-arn>,<DnsName|HostedZoneId>)
endpoint_dns = $(shell aws ec2 describe-vpc-endpoint-associations --vpc-endpoint-ids $(1) --query 'VpcEndpointAssociations[?AssociatedResourceArn == `$(2)`].DnsEntry.$(3) | [0]' --output text --region $(REGION))

deploy: check-domain deploy-common build-push deploy-central deploy-backends deploy-registry deploy-consumer deploy-dns submit-records

check-domain:
	@test -n "$(HOSTED_ZONE_NAME)" -a -n "$(CERTIFICATE_ARN)" || { echo "Set HOSTED_ZONE_NAME and CERTIFICATE_ARN (make deploy HOSTED_ZONE_NAME=example.com CERTIFICATE_ARN=arn:aws:acm:...)"; exit 1; }

# ---------- COMMON ITEMS AND IMAGES ----------
deploy-common:
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-common --template-file common.yaml --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --region $(REGION)

# ARM64 images: AgentCore Runtime runs ARM64 containers only (on an x86 machine, docker buildx needs QEMU emulation)
build-push: AGENT_REPOSITORY = $(call output,common,AgentRepositoryUri)
build-push: TRIAGE_REPOSITORY = $(call output,common,TriageRepositoryUri)
build-push:
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(firstword $(subst /, ,$(AGENT_REPOSITORY)))
	docker buildx build --platform linux/arm64 --provenance=false -t $(AGENT_REPOSITORY):latest --push $(APPLICATIONS)/agent
	docker buildx build --platform linux/arm64 --provenance=false -t $(TRIAGE_REPOSITORY):latest --push $(APPLICATIONS)/triage

# ---------- SERVICE NETWORK AND CENTRAL ENDPOINTS ----------
deploy-central:
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-central --template-file central.yaml --parameter-overrides Identifier=$(IDENTIFIER) --capabilities CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION)

# ---------- BACKENDS (MCP SERVER, REST API, A2A AGENT) ----------
deploy-backends: BUCKET = $(call output,common,ArtifactsBucket)
deploy-backends: check-domain
	mkdir -p $(BUILD_DIR)
	aws cloudformation package --template-file backends.yaml --s3-bucket $(BUCKET) --output-template-file $(BUILD_DIR)/backends.yaml --region $(REGION)
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-backends --template-file $(BUILD_DIR)/backends.yaml --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) ModelId=$(MODEL_ID) HostedZoneName=$(HOSTED_ZONE_NAME) CertificateArn=$(CERTIFICATE_ARN) \
		ServiceNetworkId=$(call output,central,ServiceNetworkId) \
		AgentEcsRoleArn=$(call output,common,AgentEcsRoleArn) AgentRuntimeRoleArn=$(call output,common,AgentRuntimeRoleArn) \
		LambdaRoleArn=$(call output,common,LambdaRoleArn) TaskExecutionRoleArn=$(call output,common,TaskExecutionRoleArn) \
		TriageRoleArn=$(call output,common,TriageRoleArn) EcsInfrastructureRoleArn=$(call output,common,EcsInfrastructureRoleArn) \
		ClusterName=$(call output,common,ClusterName) ApplicationLogGroup=$(call output,common,ApplicationLogGroup) \
		TriageImageUri=$(call output,common,TriageRepositoryUri):latest

# ---------- AWS AGENT REGISTRY ----------
deploy-registry: check-domain
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-registry --template-file agent_registry.yaml --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) HostedZoneName=$(HOSTED_ZONE_NAME)

# Records created by IaC start as drafts; submitting them makes them discoverable (the registry auto-approves)
submit-records: REGISTRY_ID = $(call output,registry,RegistryId)
submit-records: RECORD_IDS = $(call output,registry,RecordIds)
submit-records:
	for RECORD_ID in $(RECORD_IDS); do aws agent-registry-control submit-registry-record-for-approval --registry-id $(REGISTRY_ID) --record-id $$RECORD_ID --region $(REGION) || true; done

# ---------- CONSUMERS (AGENTS) ----------
# The agents have no backend URLs: they discover the services in AWS Agent Registry
deploy-consumer:
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-consumer --template-file consumer.yaml --capabilities CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) ModelId=$(MODEL_ID) AgentImageUri=$(call output,common,AgentRepositoryUri):latest \
		ServiceNetworkId=$(call output,central,ServiceNetworkId) ServiceNetworkArn=$(call output,central,ServiceNetworkArn) \
		ClusterName=$(call output,common,ClusterName) ApplicationLogGroup=$(call output,common,ApplicationLogGroup) \
		TaskExecutionRoleArn=$(call output,common,TaskExecutionRoleArn) AgentEcsRoleArn=$(call output,common,AgentEcsRoleArn) \
		AgentRuntimeRoleArn=$(call output,common,AgentRuntimeRoleArn) \
		RegistryId=$(call output,registry,RegistryId) RegistryEndpointUrl=$(call output,central,RegistryEndpointUrl)

# ---------- DNS RESOLUTION (VPC LATTICE SERVICES) ----------
# One private hosted zone per consumer VPC: aliases to the services' DNS names (VPC A) and to their DNS names on the
# service network endpoint (VPC B). A separate stack, because the endpoint's DNS names exist only after the consumer
# and backends stacks are deployed, and only the API returns them.
deploy-dns: ENDPOINT_ID = $(call output,consumer,ServiceNetworkEndpointId)
deploy-dns: SERVICE_ARNS = $(call output,backends,McpTicketsServiceArn) $(call output,backends,ApiDirectoryServiceArn) $(call output,backends,AgentTriageServiceArn)
deploy-dns: check-domain
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-dns --template-file dns.yaml --capabilities CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides HostedZoneName=$(HOSTED_ZONE_NAME) \
		ConsumerVpcAId=$(call output,consumer,ConsumerVpcAId) ConsumerVpcBId=$(call output,consumer,ConsumerVpcBId) \
		ServiceDnsNames=$(call output,backends,ServiceDnsNames) ServiceDnsHostedZoneIds=$(call output,backends,ServiceDnsHostedZoneIds) \
		EndpointDnsNames=$(subst $(space),$(comma),$(foreach arn,$(SERVICE_ARNS),$(call endpoint_dns,$(ENDPOINT_ID),$(arn),DnsName))) \
		EndpointDnsHostedZoneIds=$(subst $(space),$(comma),$(foreach arn,$(SERVICE_ARNS),$(call endpoint_dns,$(ENDPOINT_ID),$(arn),HostedZoneId)))

# ---------- TEST HELPERS ----------
# make chat AGENT=ecs|runtime: chat with a consumer agent (agent-ecs needs the Session Manager plugin for the AWS CLI)
chat:
ifeq ($(AGENT),runtime)
	python3 $(APPLICATIONS)/chat.py runtime --arn $(call output,consumer,AgentRuntimeArn)
else
	python3 $(APPLICATIONS)/chat.py ecs --cluster $(call output,common,ClusterName) --service $(call output,consumer,AgentEcsService) --region $(REGION)
endif

# make invoke-ecs PAYLOAD='{"action": "list_tools"}'  (needs the Session Manager plugin for the AWS CLI)
invoke-ecs: CLUSTER = $(call output,common,ClusterName)
invoke-ecs: TASK = $(shell aws ecs list-tasks --cluster $(call output,common,ClusterName) --service-name $(call output,consumer,AgentEcsService) --query 'taskArns[0]' --output text --region $(REGION))
invoke-ecs: PAYLOAD_B64 = $(shell printf '%s' '$(PAYLOAD)' | base64 | tr -d '\n')
invoke-ecs:
	aws ecs execute-command --cluster $(CLUSTER) --task $(TASK) --container agent --interactive --region $(REGION) --command "python /app/invoke.py $(PAYLOAD_B64)"

# make invoke-runtime PAYLOAD='{"action": "list_tools"}'
invoke-runtime:
	mkdir -p $(BUILD_DIR)
	aws bedrock-agentcore invoke-agent-runtime --agent-runtime-arn $(call output,consumer,AgentRuntimeArn) --payload '$(PAYLOAD)' --cli-binary-format raw-in-base64-out --region $(REGION) $(BUILD_DIR)/runtime-response.json > /dev/null
	python3 -m json.tool $(BUILD_DIR)/runtime-response.json

# ---------- CLEANUP ----------
undeploy: BUCKET = $(call output,common,ArtifactsBucket)
undeploy:
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-dns --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-dns --region $(REGION)
	# AgentCore Runtime ENIs can remain for some hours after the agent is deleted: if this stack fails to delete, retry later
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-consumer --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-consumer --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-registry --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-backends --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-registry --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-backends --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-central --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-central --region $(REGION)
	aws s3 rm s3://$(BUCKET) --recursive --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-common --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-common --region $(REGION)

.PHONY: deploy check-domain deploy-common build-push deploy-central deploy-registry deploy-backends deploy-gateway deploy-consumer deploy-dns submit-records chat invoke-ecs invoke-runtime undeploy

REGION ?= eu-west-1
STACK_PREFIX = vpclattice-agentic-gateway
IDENTIFIER ?= agentic-gateway
MODEL_ID ?= eu.anthropic.claude-haiku-5-5
# Required: domain of the services' custom domain names, and an ACM certificate that covers *.<HOSTED_ZONE_NAME>
HOSTED_ZONE_NAME ?=
CERTIFICATE_ARN ?=
PAYLOAD ?= {"action": "whoami"}
AGENT ?= ecs
APPLICATIONS = ../../applications
BUILD_DIR = .build

# Read a stack output: $(call output,<stack-suffix>,<OutputKey>)
output = $(shell aws cloudformation describe-stacks --stack-name $(STACK_PREFIX)-$(1) --query 'Stacks[0].Outputs[?OutputKey == `$(2)`].OutputValue' --output text --region $(REGION))
# DNS entry VPC Lattice created for a service on the service network endpoint: $(call endpoint_dns,<endpoint-id>,<service-arn>,<DnsName|HostedZoneId>)
endpoint_dns = $(shell aws ec2 describe-vpc-endpoint-associations --vpc-endpoint-ids $(1) --query 'VpcEndpointAssociations[?AssociatedResourceArn == `$(2)`].DnsEntry.$(3) | [0]' --output text --region $(REGION))

deploy: check-domain deploy-common build-push deploy-central deploy-registry submit-records deploy-backends deploy-gateway deploy-consumer deploy-dns

check-domain:
	@test -n "$(HOSTED_ZONE_NAME)" -a -n "$(CERTIFICATE_ARN)" || { echo "Set HOSTED_ZONE_NAME and CERTIFICATE_ARN (make deploy HOSTED_ZONE_NAME=example.com CERTIFICATE_ARN=arn:aws:acm:...)"; exit 1; }

# ---------- COMMON ITEMS AND IMAGES ----------
deploy-common:
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-common --template-file common.yaml --parameter-overrides Identifier=$(IDENTIFIER) --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION)

# ARM64 images: AgentCore Runtime runs ARM64 containers only (on an x86 machine, docker buildx needs QEMU emulation).
# The gateway image is built from the applications/ directory with -f litellm/Dockerfile (it bundles the OpenAPI spec).
build-push: AGENT_REPOSITORY = $(call output,common,AgentRepositoryUri)
build-push: TRIAGE_REPOSITORY = $(call output,common,TriageRepositoryUri)
build-push: GATEWAY_REPOSITORY = $(call output,common,GatewayRepositoryUri)
build-push:
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(firstword $(subst /, ,$(AGENT_REPOSITORY)))
	docker buildx build --platform linux/arm64 --provenance=false -t $(AGENT_REPOSITORY):latest --push $(APPLICATIONS)/agent
	docker buildx build --platform linux/arm64 --provenance=false -t $(TRIAGE_REPOSITORY):latest --push $(APPLICATIONS)/triage
	docker buildx build --platform linux/arm64 --provenance=false -t $(GATEWAY_REPOSITORY):latest --push -f $(APPLICATIONS)/litellm/Dockerfile $(APPLICATIONS)

# ---------- SERVICE NETWORKS, CENTRAL ENDPOINTS AND GATEWAY VPC ----------
deploy-central:
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-central --template-file central.yaml --parameter-overrides Identifier=$(IDENTIFIER) --capabilities CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION)

# ---------- AWS AGENT REGISTRY ----------
# The records point at the gateway's custom domain name, so the registry only needs the domain
deploy-registry: check-domain
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-registry --template-file agent_registry.yaml --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) HostedZoneName=$(HOSTED_ZONE_NAME)

# Records created by IaC start as drafts; submitting them makes them discoverable (the registry auto-approves).
# Submitted before the backends: triage starts serving only once it finds the gateway's model record, and
# CloudFormation waits for the triage service to be stable
submit-records: REGISTRY_ID = $(call output,registry,RegistryId)
submit-records: RECORD_IDS = $(call output,registry,RecordIds)
submit-records:
	for RECORD_ID in $(RECORD_IDS); do aws agent-registry-control submit-registry-record-for-approval --registry-id $(REGISTRY_ID) --record-id $$RECORD_ID --region $(REGION) || true; done

# ---------- BACKENDS (MCP SERVER, REST API, A2A AGENT) ----------
deploy-backends: BUCKET = $(call output,common,ArtifactsBucket)
deploy-backends: check-domain
	mkdir -p $(BUILD_DIR)
	aws cloudformation package --template-file backends.yaml --s3-bucket $(BUCKET) --output-template-file $(BUILD_DIR)/backends.yaml --region $(REGION)
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-backends --template-file $(BUILD_DIR)/backends.yaml --capabilities CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) HostedZoneName=$(HOSTED_ZONE_NAME) CertificateArn=$(CERTIFICATE_ARN) \
		BackendsServiceNetworkId=$(call output,central,BackendsServiceNetworkId) AgentsServiceNetworkId=$(call output,central,AgentsServiceNetworkId) \
		GatewayVpcId=$(call output,central,GatewayVpcId) \
		RegistryId=$(call output,registry,RegistryId) RegistryEndpointUrl=$(call output,central,RegistryEndpointUrl) \
		AgentTriageKeyArn=$(call output,common,AgentTriageKeyArn) \
		LambdaRoleArn=$(call output,common,LambdaRoleArn) TaskExecutionRoleArn=$(call output,common,TaskExecutionRoleArn) \
		TriageRoleArn=$(call output,common,TriageRoleArn) EcsInfrastructureRoleArn=$(call output,common,EcsInfrastructureRoleArn) \
		ClusterName=$(call output,common,ClusterName) ApplicationLogGroup=$(call output,common,ApplicationLogGroup) \
		TriageImageUri=$(call output,common,TriageRepositoryUri):latest VpcLatticePrefixListId=$(call output,common,VpcLatticePrefixListId)

# ---------- AI GATEWAY ----------
deploy-gateway: check-domain
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-gateway --template-file gateway.yaml --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) ModelId=$(MODEL_ID) HostedZoneName=$(HOSTED_ZONE_NAME) CertificateArn=$(CERTIFICATE_ARN) \
		AgentsServiceNetworkId=$(call output,central,AgentsServiceNetworkId) \
		GatewayVpcId=$(call output,central,GatewayVpcId) GatewaySubnets=$(call output,central,GatewaySubnets) \
		GatewayVpcLatticeSecurityGroupId=$(call output,central,GatewayVpcLatticeSecurityGroupId) VpcLatticePrefixListId=$(call output,common,VpcLatticePrefixListId) \
		ClusterName=$(call output,common,ClusterName) ApplicationLogGroup=$(call output,common,ApplicationLogGroup) \
		TaskExecutionRoleArn=$(call output,common,TaskExecutionRoleArn) GatewayRoleArn=$(call output,common,GatewayRoleArn) \
		EcsInfrastructureRoleArn=$(call output,common,EcsInfrastructureRoleArn) GatewayImageUri=$(call output,common,GatewayRepositoryUri):latest \
		AgentEcsRoleArn=$(call output,common,AgentEcsRoleArn) AgentRuntimeRoleArn=$(call output,common,AgentRuntimeRoleArn) \
		TriageRoleArn=$(call output,common,TriageRoleArn) \
		LiteLLMMasterKeyArn=$(call output,common,LiteLLMMasterKeyArn) AgentEcsKeyArn=$(call output,common,AgentEcsKeyArn) \
		AgentRuntimeKeyArn=$(call output,common,AgentRuntimeKeyArn) AgentTriageKeyArn=$(call output,common,AgentTriageKeyArn) \
		McpTicketsUrl=$(call output,backends,McpTicketsUrl) ApiDirectoryUrl=$(call output,backends,ApiDirectoryUrl) \
		AgentTriageUrl=$(call output,backends,AgentTriageUrl) \
		BackendDnsNames=$(call output,backends,ServiceDnsNames) BackendDnsHostedZoneIds=$(call output,backends,ServiceDnsHostedZoneIds)

# ---------- CONSUMERS (AGENTS) ----------
# The agents have no gateway URL or model: they find the gateway's endpoints in AWS Agent Registry
deploy-consumer:
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-consumer --template-file consumer.yaml --capabilities CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) AgentImageUri=$(call output,common,AgentRepositoryUri):latest \
		AgentsServiceNetworkId=$(call output,central,AgentsServiceNetworkId) AgentsServiceNetworkArn=$(call output,central,AgentsServiceNetworkArn) \
		ClusterName=$(call output,common,ClusterName) ApplicationLogGroup=$(call output,common,ApplicationLogGroup) \
		TaskExecutionRoleArn=$(call output,common,TaskExecutionRoleArn) AgentEcsRoleArn=$(call output,common,AgentEcsRoleArn) \
		AgentRuntimeRoleArn=$(call output,common,AgentRuntimeRoleArn) \
		AgentEcsKeyArn=$(call output,common,AgentEcsKeyArn) AgentRuntimeKeyArn=$(call output,common,AgentRuntimeKeyArn) \
		RegistryId=$(call output,registry,RegistryId) RegistryEndpointUrl=$(call output,central,RegistryEndpointUrl)

# ---------- DNS RESOLUTION (AI-GATEWAY SERVICE) ----------
# Private hosted zones for the ai-gateway custom domain name: aliases to the service's DNS name (consumer VPC A and the
# provider VPC) and to its DNS name on the service network endpoint (consumer VPC B). A separate stack, because the
# endpoint's DNS name exists only after the consumer and gateway stacks are deployed, and only the API returns it.
deploy-dns: ENDPOINT_ID = $(call output,consumer,ServiceNetworkEndpointId)
deploy-dns: SERVICE_ARN = $(call output,gateway,AiGatewayServiceArn)
deploy-dns: check-domain
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-dns --template-file dns.yaml --capabilities CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides HostedZoneName=$(HOSTED_ZONE_NAME) \
		ConsumerVpcAId=$(call output,consumer,ConsumerVpcAId) ConsumerVpcBId=$(call output,consumer,ConsumerVpcBId) \
		ProviderVpcId=$(call output,backends,ProviderVpcId) \
		ServiceDnsName=$(call output,gateway,AiGatewayDnsName) ServiceDnsHostedZoneId=$(call output,gateway,AiGatewayDnsHostedZoneId) \
		EndpointDnsName=$(call endpoint_dns,$(ENDPOINT_ID),$(SERVICE_ARN),DnsName) \
		EndpointDnsHostedZoneId=$(call endpoint_dns,$(ENDPOINT_ID),$(SERVICE_ARN),HostedZoneId)

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
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-gateway --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-gateway --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-backends --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-registry --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-backends --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-registry --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-central --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-central --region $(REGION)
	aws s3 rm s3://$(BUCKET) --recursive --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-common --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-common --region $(REGION)

.PHONY: deploy check-domain deploy-common build-push deploy-gateway deploy-central deploy-registry submit-records deploy-backends deploy-targets deploy-consumer chat invoke-ecs invoke-runtime undeploy

REGION ?= eu-west-1
STACK_PREFIX = vpclattice-agentic-core
IDENTIFIER ?= agentic-core
MODEL_ID ?= anthropic.claude-haiku-4-5
# Required: domain of the VPC-hosted backends' names, and an ACM public certificate that covers *.<DOMAIN_NAME>
DOMAIN_NAME ?=
CERTIFICATE_ARN ?=
PAYLOAD ?= {"action": "whoami"}
AGENT ?= ecs
APPLICATIONS = ../../applications
BUILD_DIR = .build

# Read a stack output: $(call output,<stack-suffix>,<OutputKey>)
output = $(shell aws cloudformation describe-stacks --stack-name $(STACK_PREFIX)-$(1) --query 'Stacks[0].Outputs[?OutputKey == `$(2)`].OutputValue' --output text --region $(REGION))

# The gateway comes before the central endpoints: its DNS name, which contains its ID, is the custom domain name of
# its resource configuration
deploy: check-domain deploy-common build-push deploy-gateway deploy-central deploy-registry submit-records deploy-backends deploy-targets deploy-consumer

check-domain:
	@test -n "$(DOMAIN_NAME)" -a -n "$(CERTIFICATE_ARN)" || { echo "Set DOMAIN_NAME and CERTIFICATE_ARN (make deploy DOMAIN_NAME=example.com CERTIFICATE_ARN=arn:aws:acm:...)"; exit 1; }

# ---------- COMMON ITEMS AND IMAGES ----------
# The gateway's service role is here, a stack before the gateway, so IAM has propagated it when the gateway is created
deploy-common:
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-common --template-file common.yaml --parameter-overrides Identifier=$(IDENTIFIER) --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --region $(REGION)

# ARM64 images: AgentCore Runtime runs ARM64 containers only (on an x86 machine, docker buildx needs QEMU emulation)
build-push: AGENT_REPOSITORY = $(call output,common,AgentRepositoryUri)
build-push: TRIAGE_REPOSITORY = $(call output,common,TriageRepositoryUri)
build-push: TICKETS_REPOSITORY = $(call output,common,TicketsRepositoryUri)
build-push:
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(firstword $(subst /, ,$(AGENT_REPOSITORY)))
	docker buildx build --platform linux/arm64 --provenance=false -t $(AGENT_REPOSITORY):latest --push $(APPLICATIONS)/agent
	docker buildx build --platform linux/arm64 --provenance=false -t $(TRIAGE_REPOSITORY):latest --push $(APPLICATIONS)/triage
	docker buildx build --platform linux/arm64 --provenance=false -t $(TICKETS_REPOSITORY):latest --push $(APPLICATIONS)/mcp_tickets

# ---------- AGENTCORE GATEWAY (NATIVE TARGETS) ----------
deploy-gateway: BUCKET = $(call output,common,ArtifactsBucket)
deploy-gateway:
	mkdir -p $(BUILD_DIR)
	aws cloudformation package --template-file gateway.yaml --s3-bucket $(BUCKET) --output-template-file $(BUILD_DIR)/gateway.yaml --region $(REGION)
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-gateway --template-file $(BUILD_DIR)/gateway.yaml --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) GatewayRoleArn=$(call output,common,GatewayRoleArn) LambdaRoleArn=$(call output,common,LambdaRoleArn) \
		AgentEcsRoleArn=$(call output,common,AgentEcsRoleArn) AgentRuntimeRoleArn=$(call output,common,AgentRuntimeRoleArn) \
		TriageRoleArn=$(call output,common,TriageRoleArn)

# ---------- SERVICE NETWORK AND CENTRAL ENDPOINTS ----------
deploy-central:
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-central --template-file central.yaml --capabilities CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) GatewayId=$(call output,gateway,GatewayId)

# ---------- AWS AGENT REGISTRY ----------
deploy-registry:
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-registry --template-file agent_registry.yaml --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) GatewayUrl=$(call output,gateway,GatewayUrl) ModelId=$(MODEL_ID)

# Records created by IaC start as drafts; submitting them makes them discoverable (the registry auto-approves).
# Submitted before the backends: triage starts serving only once it finds the gateway's model record, and
# CloudFormation waits for the triage service to be stable
submit-records: REGISTRY_ID = $(call output,registry,RegistryId)
submit-records: RECORD_IDS = $(call output,registry,RecordIds)
submit-records:
	for RECORD_ID in $(RECORD_IDS); do aws agent-registry-control submit-registry-record-for-approval --registry-id $(REGISTRY_ID) --record-id $$RECORD_ID --region $(REGION) || true; done

# ---------- VPC-HOSTED BACKENDS (TICKETS AND TRIAGE) ----------
deploy-backends: check-domain
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-backends --template-file backends.yaml --capabilities CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) CertificateArn=$(CERTIFICATE_ARN) \
		ServiceNetworkId=$(call output,central,ServiceNetworkId) GatewayUrl=$(call output,gateway,GatewayUrl) \
		RegistryId=$(call output,registry,RegistryId) RegistryEndpointUrl=$(call output,central,RegistryEndpointUrl) \
		TaskExecutionRoleArn=$(call output,common,TaskExecutionRoleArn) TriageRoleArn=$(call output,common,TriageRoleArn) \
		ClusterName=$(call output,common,ClusterName) ApplicationLogGroup=$(call output,common,ApplicationLogGroup) \
		TicketsImageUri=$(call output,common,TicketsRepositoryUri):latest TriageImageUri=$(call output,common,TriageRepositoryUri):latest

# ---------- AGENTCORE GATEWAY (VPC-HOSTED TARGETS AND POLICY) ----------
deploy-targets: check-domain
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-targets --template-file targets.yaml --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides DomainName=$(DOMAIN_NAME) \
		GatewayId=$(call output,gateway,GatewayId) GatewayArn=$(call output,gateway,GatewayArn) PolicyEngineId=$(call output,gateway,PolicyEngineId) \
		TicketsResourceConfigurationArn=$(call output,backends,TicketsResourceConfigurationArn) \
		TriageResourceConfigurationArn=$(call output,backends,TriageResourceConfigurationArn) \
		AgentEcsRoleArn=$(call output,common,AgentEcsRoleArn) AgentRuntimeRoleArn=$(call output,common,AgentRuntimeRoleArn) \
		TriageRoleArn=$(call output,common,TriageRoleArn)

# ---------- CONSUMERS (AGENTS) ----------
# The agents have no gateway URL or model: they find the gateway's endpoints in AWS Agent Registry
deploy-consumer:
	aws cloudformation deploy --stack-name $(STACK_PREFIX)-consumer --template-file consumer.yaml --capabilities CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --region $(REGION) \
		--parameter-overrides Identifier=$(IDENTIFIER) AgentImageUri=$(call output,common,AgentRepositoryUri):latest \
		ServiceNetworkId=$(call output,central,ServiceNetworkId) \
		ClusterName=$(call output,common,ClusterName) ApplicationLogGroup=$(call output,common,ApplicationLogGroup) \
		TaskExecutionRoleArn=$(call output,common,TaskExecutionRoleArn) AgentEcsRoleArn=$(call output,common,AgentEcsRoleArn) \
		AgentRuntimeRoleArn=$(call output,common,AgentRuntimeRoleArn) \
		RegistryId=$(call output,registry,RegistryId) RegistryEndpointUrl=$(call output,central,RegistryEndpointUrl)

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
# The targets go before the backends (they use the backends' resource configurations), and the central endpoints and
# the gateway go after everything that uses them
undeploy: BUCKET = $(call output,common,ArtifactsBucket)
undeploy:
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-consumer --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-targets --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-consumer --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-targets --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-backends --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-registry --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-backends --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-registry --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-central --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-central --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-gateway --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-gateway --region $(REGION)
	aws s3 rm s3://$(BUCKET) --recursive --region $(REGION)
	aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-common --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-common --region $(REGION)

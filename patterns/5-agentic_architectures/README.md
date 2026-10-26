# Amazon VPC Lattice Blueprints - Agentic Architectures

## Overview

This section shows how Amazon VPC Lattice simplifies the communication of AI agents. Agents call three kinds of things: **tools** (MCP servers), **APIs** (REST) and **other agents** (A2A), plus a **model**. Each pattern connects the same helpdesk workload (a `tickets` MCP server, a `directory` REST API and a `triage` agent) to two consumer agents, one self-hosted and one on Amazon Bedrock AgentCore Runtime, with or without an AI gateway in between.

**Use this section to**:

- Connect agents to MCP servers, REST APIs, other agents and models across VPCs and accounts, with access decided on the agent's identity.
- Place an AI gateway, self-hosted or managed, in VPC Lattice: one endpoint for every agent, and private paths to every backend.
- Discover tools, APIs, agents and models with AWS Agent Registry, so the agents don't hold any backend configuration.

> **Note**: These patterns assume familiarity with VPC Lattice services and VPC resources. If you're new to VPC Lattice, start with [Simple Architectures](../1-simple_architectures/).

## Simple, governed and discoverable agentic communication

Agentic architectures multiply the connections: every agent can call many tools, APIs, agents and models, owned by different teams, in different VPCs and accounts. VPC Lattice simplifies the network, so you can focus on the granular controls and the discovery.

### Connectivity: Amazon VPC Lattice

| Challenge | What VPC Lattice does |
|-----------|----------------------|
| **Many-to-many connectivity** across VPCs and accounts | One service network connects every agent and backend. No VPC peering, transit gateway, route tables or NAT, and the VPCs can share the same CIDR (all of them use `10.0.0.0/16` here). Across accounts, the service network, services and resource configurations are shared over AWS RAM |
| **Knowing which agent is calling** | Every request to a VPC Lattice service can be signed with the agent's IAM role (SigV4), and auth policies decide per service, HTTP method and path which agent may call it |
| **AWS endpoints in every agent VPC** (Amazon Bedrock, AgentCore, AWS Agent Registry, Amazon ECR, CloudWatch Logs) | The interface endpoints are centralized once and published as VPC resources in the service network, as in [Centralized VPC Endpoints](../3-advanced_architectures/1-centralized_vpc_endpoints/). The agent VPCs need no internet access and no endpoints of their own |
| **Auditing who called what** | Access logs record every request to a service (caller, auth decision, path and status code) and every connection to a resource |

> **Note**: VPC Lattice allows or denies an MCP server as a whole, not per tool, because MCP sends every call as a `POST` to one path. Per-tool, per-model and budget decisions belong to the application or to an AI gateway.

### Granular controls: AI gateway and user identity

An AI gateway gives agents one entry point to their models, tools and agents, and decides what each agent may use: per tool, per agent and per model, with budgets and model routing. Whether to add one is an architecture decision; the patterns show how each setup plugs into VPC Lattice. Together, they cover the agentic communication at scale:

- **VPC Lattice connects agents to the gateway**: the gateway is reached through one service network, as a VPC Lattice service (self-hosted) or a VPC resource (Amazon Bedrock AgentCore Gateway). Adding a consumer VPC adds a VPC association or a service network endpoint, not another path to the gateway.
- **VPC Lattice connects the gateway to the backends**: each backend is published once, as a service or a resource configuration, and can stay in its owner's VPC and account. AgentCore Gateway itself uses VPC Lattice resource configurations to reach private targets.
- **VPC Lattice keeps the gateway the only path**: service networks and auth policies decide who reaches the gateway and what the gateway reaches, so the agents can't bypass it.
- **The gateway decides per request what each agent may use**, which the network can't do for MCP tools or models.

The finest control is the **user**. The patterns authorize the agent (its IAM role, virtual key or Cedar policy), not the user the agent acts for. User-level decisions (*Ana may read her own tickets, not everyone's*) need the user's identity to travel with the request:

- **Without an AI gateway**, the backends make the user-level decisions: [Amazon Bedrock AgentCore Identity](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/on-behalf-of-token-exchange.html) exchanges the user's token for one scoped to each backend, carrying both the user's and the agent's identity, while VPC Lattice still decides which agent may call.
- **With an AI gateway**, the gateway is the natural place: it validates the user's token from your identity provider, applies per-user permissions, and passes the user's identity on to the backends. AgentCore Identity can handle the tokens on either side: the agent obtains a token for the gateway on behalf of the user, and AgentCore Gateway uses AgentCore Identity for its [outbound authorization](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-outbound-auth.html) to the backends, including the on-behalf-of (OBO) token exchange.

> **Note**: Each pattern's Security architecture explains where user identity fits, but the patterns don't deploy it, to keep the focus on the connectivity. It builds on the same network without changes.

### Discovery: AWS Agent Registry

The agents only know where [AWS Agent Registry](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/registry.html) is. On every request, they read its records (MCP servers, A2A agent cards, REST APIs and model endpoints) and call the endpoints the records describe:

- **Without an AI gateway**, the records point at the backends themselves.
- **With an AI gateway**, the records point at the gateway's endpoints, because the agents can only reach the gateway. The gateway then lists the tools each agent may use.

Adding, moving or retiring a backend, or putting a gateway in front of the backends, means updating records, not agents. Discovery doesn't grant access: VPC Lattice and the AI gateway still decide every call. Agents in a VPC reach the registry through its centralized endpoint in the service network, and the registry can be [shared over AWS RAM](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/registry-cross-account-sharing.html) with agents in other accounts.

## Self-hosted agents and agents on AgentCore Runtime

Every pattern runs the same agent code ([`applications/agent/`](./applications/agent/)) in two places, to show how each kind of agent connects:

| Agent | Where it runs | How it connects |
|-------|---------------|-----------------|
| **`agent-ecs`** | Self-hosted, on Amazon ECS in consumer VPC A | A VPC association to the service network |
| **`agent-runtime`** | Amazon Bedrock AgentCore Runtime | In VPC mode in consumer VPC B, through a service network endpoint (patterns 1 and 2). With no VPC, calling AgentCore Gateway directly with its IAM role (pattern 3) |

Both agents read the same registry records and call the same URLs: in each VPC, private DNS and private hosted zones resolve the names to VPC Lattice, and `agent-runtime` without a VPC resolves AgentCore Gateway's name with public DNS.

## Architecture Patterns

| Pattern | Description | IaC Support |
|---------|-------------|-------------|
| [1. Direct Agent Connectivity](./1-direct_agent_connectivity/) | No AI gateway: the MCP server, REST API and triage agent are VPC Lattice services, and auth policies decide which agent may call which service | CloudFormation, Terraform |
| [2. Self-Hosted AI Gateway](./2-self_hosted_ai_gateway/) | A self-hosted AI gateway (LiteLLM as the example) as a VPC Lattice service: the agents reach it in one service network, and it reaches the backends and the model in another, so it's the only path to them | CloudFormation, Terraform |
| [3. Amazon Bedrock AgentCore Gateway](./3-agentcore_gateway/) | A managed AI gateway: native targets where AgentCore has them, one centralized gateway endpoint for agents in a VPC, and VPC Lattice resource configurations for backends in their own VPCs | CloudFormation, Terraform |

All patterns build their agents, triage agent, tools and gateway from the shared [`applications/`](./applications/) directory.

## Comparing the patterns

| | Direct | Self-hosted AI gateway | AgentCore Gateway |
|---|---|---|---|
| **Who decides access** | VPC Lattice auth policies, on the agent's IAM identity (per service, HTTP method and path) | VPC Lattice (who reaches the gateway), then the gateway with each agent's virtual key (per tool, agent and model) | IAM (who may invoke the gateway), then the gateway's policy engine in Cedar (per tool, agent and model) |
| **What VPC Lattice carries** | Agents to the backends, and to the AWS endpoints | Agents to the gateway, and the gateway to the backends and the model | Agents in a VPC to the gateway, and the gateway to backends in a VPC |
| **Where the backends are published** | VPC Lattice services | VPC Lattice services | Native targets, or resource configurations for backends in a VPC |
| **What the registry records point at** | The backends | The gateway | The gateway |
| **User identity (described, not deployed)** | Each backend, with AgentCore Identity | The gateway, with the user's token from your identity provider (obtained by the agent through AgentCore Identity, for example) | AgentCore Gateway: JWT inbound authorization, Cedar rules on the user, and on-behalf-of token exchange to the targets |

## Prerequisites

- **Amazon Bedrock model access** for the model each pattern uses (`model_id` in Terraform, `MODEL_ID` in CloudFormation; each pattern README gives its default).
- **Docker with `buildx`**, to build `linux/arm64` images (AgentCore Runtime runs ARM64 containers).
- **A Region where AgentCore Runtime VPC mode, AgentCore Gateway and AWS Agent Registry are available**, with Availability Zone IDs that AgentCore Runtime supports. See [Supported Availability Zones](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-vpc.html#agentcore-supported-azs).

> **Note**: Each pattern's default model is an example. Use the model your organization approves and that fits your use case (quality, latency, cost and data residency).

## Next Steps

After exploring these patterns:

1. **[Auth Policies & SigV4](../4-auth_policies/)** - Reference toolkit for restricting which agents can call each service
2. **[Multi-Account Patterns](../2-multi_account/)** - Share the service network, services and resource configurations across accounts

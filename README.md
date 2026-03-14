# Platform

One command to spin up a full internal developer platform. An event-driven CI/CD, observability stack, and GitOps infrastructure pipeline running locally in 10 minutes or less.

---

## What Gets Built

This repo connects three projects into a single platform:

- **[argo-event-pipeline](https://github.com/SmartBrisco/argo-event-pipeline)** — Event-driven CI/CD pipeline on Kubernetes using Argo Events and Argo Workflows, with Trivy security scanning and AI-powered failure analysis via Ollama
- **[platform-observability](https://github.com/SmartBrisco/platform-observability)** — Full-stack observability with OpenTelemetry, Jaeger, Prometheus, and Grafana receiving live telemetry from the Argo pipeline
- **[gitops-infra-pipeline](https://github.com/SmartBrisco/gitops-infra-pipeline)** — GitHub Actions and Terraform pipeline provisioning AWS infrastructure on every commit with OIDC authentication and multi-channel Slack notifications

`make platform-up` handles the Kubernetes platform entirely locally. The GitOps infrastructure pipeline runs automatically via GitHub Actions on push to main in that repo.

---

## Local Prerequisites

Install these before running anything:

| Tool | Purpose |
|------|---------|
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Kubernetes CLI |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/) | Local Kubernetes cluster |
| [argo CLI](https://argo-workflows.readthedocs.io/en/latest/walk-through/argo-cli/) | Argo Workflows CLI |
| [terraform](https://developer.hashicorp.com/terraform/install) | Infrastructure as code |
| [trivy](https://aquasecurity.github.io/trivy/latest/getting-started/installation/) | Security scanning |

Run `make check-prereqs` to verify all tools are installed before proceeding.

---

## One-Time Setup (GitOps Infrastructure Pipeline Only)

These steps are required once before the Terraform validation targets will work. They are not required for `make platform-up`.

### 1. AWS OIDC Configuration

Create an IAM OIDC Identity Provider in your AWS account:

```
Provider URL: https://token.actions.githubusercontent.com
Audience: sts.amazonaws.com
```

Create an IAM Role with a trust policy scoped to your fork of `gitops-infra-pipeline`. Attach policies: `AmazonEC2FullAccess`, `AmazonVPCFullAccess`, `SecretsManagerReadWrite`.

> This works with any cloud provider that supports OIDC federation with GitHub Actions. Replace the AWS-specific Terraform module with your provider of choice and the rest of the platform stays the same.

### 2. Slack Webhooks

Create a Slack app at [api.slack.com/apps](https://api.slack.com/apps). Enable Incoming Webhooks and create three webhooks pointed at:

- `#infra-deployments`
- `#infra-alerts`
- `#infra-audit`

### 3. GitHub Secrets

Add to your fork of `gitops-infra-pipeline` under Settings → Secrets and variables → Actions:

| Secret | Value |
|--------|-------|
| `AWS_ROLE_ARN` | ARN of the IAM role created above |
| `SLACK_WEBHOOK_DEPLOYMENTS` | Webhook URL for deployments channel |
| `SLACK_WEBHOOK_ALERTS` | Webhook URL for alerts channel |
| `SLACK_WEBHOOK_AUDIT` | Webhook URL for audit channel |

---

## Usage

### Spin up the full platform

```bash
git clone <this-repo>
cd platform
make platform-up
```

That's it. The Makefile handles the rest:

1. Clones all three project repos
2. Creates a local kind cluster
3. Creates all required namespaces
4. Installs Argo Workflows and Argo Events
5. Applies RBAC
6. Deploys all manifests
7. Pulls the TinyLlama model into the cluster
8. Deploys the full observability stack
9. Port-forwards the webhook and Argo UI
10. Fires a test webhook and confirms the pipeline runs

### Access the UIs

After `make platform-up` completes:

| Service | URL |
|---------|-----|
| Argo UI | https://localhost:2746 |
| Grafana | http://localhost:3000 (admin/admin) |
| Prometheus | http://localhost:9090 |
| Jaeger | http://localhost:16686 |
| Webhook | http://localhost:12000/push |

### Terraform validation (optional)

For local validation of the GitOps infrastructure pipeline before pushing:

```bash
make tf-init       # Initialize Terraform
make tf-validate   # Format check, validate, tflint
make tf-scan       # Trivy IaC scan
```

Requires AWS credentials configured locally. The actual `terraform apply` runs automatically via GitHub Actions on push to main in `gitops-infra-pipeline`.

---

## Individual Targets

| Target | Description |
|--------|-------------|
| `make check-prereqs` | Verify required tools are installed |
| `make clone` | Clone all three project repos |
| `make cluster-create` | Create the kind cluster |
| `make namespaces` | Create all required namespaces |
| `make argo-install` | Install Argo Workflows |
| `make argo-event-install` | Install Argo Events and EventBus |
| `make apply-rbac` | Apply RBAC manifests |
| `make deploy-manifest` | Deploy Argo pipeline manifests |
| `make pull-tiny-llama-model` | Pull TinyLlama into the cluster |
| `make port-forwarding` | Port-forward webhook and Argo UI |
| `make run-test` | Fire a test webhook |
| `make deploy-jaeger` | Deploy Jaeger |
| `make deploy-prometheus` | Deploy Prometheus |
| `make deploy-grafana` | Deploy Grafana |
| `make deploy-otel` | Deploy OTel Collector |
| `make verify` | Verify all monitoring pods are running |
| `make tf-init` | Initialize Terraform |
| `make tf-validate` | Run fmt, validate, and tflint |
| `make tf-scan` | Run Trivy IaC scan |
| `make platform-up` | Spin up the full platform |

---

## Part of a Three-Project Platform Engineering Portfolio

- **Project 1** — [argo-event-pipeline](https://github.com/SmartBrisco/argo-event-pipeline) — Event-driven CI/CD with AI-powered failure analysis
- **Project 2** — [gitops-infra-pipeline](https://github.com/SmartBrisco/gitops-infra-pipeline) — GitHub Actions and Terraform infrastructure automation
- **Project 3** — [platform-observability](https://github.com/SmartBrisco/platform-observability) — Unified observability with OpenTelemetry, Jaeger, Prometheus, and Grafana

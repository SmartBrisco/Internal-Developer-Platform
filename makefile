CLUSTER_NAME = my-cluster

.PHONY: check-prereqs cluster-create namespaces clone operator-install operator-deploy-sample argo-install operator-run argo-event-install apply-rbac deploy-manifest pull-tiny-llama-model port-forwarding run-test deploy-jaeger deploy-prometheus deploy-grafana deploy-otel verify tf-bootstrap tf-init tf-policy tf-validate tf-scan kargo-install kargo-login kargo-setup kargo-promote-dev kargo-promote-prod platform-up teardown

clone:
	git clone https://github.com/SmartBrisco/argo-event-pipeline || true
	git clone https://github.com/SmartBrisco/gitops-infra-pipeline || true
	git clone https://github.com/SmartBrisco/platform-observability || true
	git clone https://github.com/SmartBrisco/namespace-provisioner || true

check-prereqs:
	@echo "Checking required tools..."
	@command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found. Install: https://kubernetes.io/docs/tasks/tools/"; exit 1; }
	@command -v kind >/dev/null 2>&1 || { echo "kind not found. Install: https://kind.sigs.k8s.io/docs/user/quick-start/"; exit 1; }
	@command -v argo >/dev/null 2>&1 || { echo "argo CLI not found. Install: https://argo-workflows.readthedocs.io/en/latest/walk-through/argo-cli/"; exit 1; }
	@command -v go >/dev/null 2>&1 || { echo "go not found. Install: https://go.dev/doc/install"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "terraform not found. Install: https://developer.hashicorp.com/terraform/install"; exit 1; }
	@command -v trivy >/dev/null 2>&1 || { echo "trivy not found. Install: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"; exit 1; }
	@command -v conftest >/dev/null 2>&1 || { echo "conftest not found. Install: https://www.conftest.dev/install/"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "helm not found. Install: https://helm.sh/docs/intro/install/"; exit 1; }
	@command -v kargo >/dev/null 2>&1 || { echo "kargo CLI not found. Install: https://github.com/akuity/kargo/releases/latest"; exit 1; }
	@echo "All prerequisites satisfied."

cluster-create: clone
	kind get clusters | grep -q $(CLUSTER_NAME) || kind create cluster --name $(CLUSTER_NAME)

namespaces: cluster-create
	kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace argo-events --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace argo-workflows --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

operator-install: namespaces
	cd namespace-provisioner && make install

operator-run:
	cd namespace-provisioner && make run

operator-deploy-sample:
	kubectl apply -f namespace-provisioner/config/samples/platform_v1alpha1_managednamespace.yaml

argo-install: namespaces
	kubectl apply --server-side -f https://github.com/argoproj/argo-workflows/releases/latest/download/quick-start-minimal.yaml
	kubectl wait --for=condition=available deployment/argo-server -n argo --timeout=120s
	kubectl patch configmap workflow-controller-configmap -n argo --type merge -p '{"data":{"artifactRepository":"archiveLogs: false\n"}}'

argo-event-install: namespaces
	kubectl apply -n argo-events -f https://github.com/argoproj/argo-events/releases/latest/download/install.yaml
	kubectl apply -n argo-events -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml
	@echo "Waiting for argo-events controller..."
	kubectl wait --for=condition=ready pod -l app=controller-manager -n argo-events --timeout=120s
	@echo "Waiting for eventbus to be provisioned..."
	kubectl wait --for=condition=ready pod -l eventbus-name=default -n argo-events --timeout=180s

apply-rbac: argo-install argo-event-install
	kubectl apply --force -f argo-event-pipeline/rbac/clusterrole.yaml
	kubectl apply --force -f argo-event-pipeline/rbac/clusterrolebinding.yaml

deploy-manifest: apply-rbac
	kubectl apply -f argo-event-pipeline/manifest/eventsource-webhook.yaml
	kubectl apply -f argo-event-pipeline/manifest/eventsource-svc.yaml
	kubectl apply -f argo-event-pipeline/manifest/ollama-deployment.yaml
	kubectl apply -f argo-event-pipeline/manifest/sensor-webhook.yaml
	@echo "Waiting for eventbus..."
	kubectl wait --for=condition=ready pod -l eventbus-name=default -n argo-events --timeout=180s
	@echo "Waiting for webhook eventsource pod..."
	kubectl wait --for=condition=ready pod -l eventsource-name=webhook -n argo-events --timeout=180s

pull-tiny-llama-model: deploy-manifest
	kubectl wait --for=condition=ready pod -l app=ollama -n argo-workflows --timeout=300s
	kubectl exec -n argo-workflows deployment/ollama -- ollama pull tinyllama

port-forwarding: deploy-manifest
	pkill -f "port-forward.*webhook-eventsource" || true
	pkill -f "port-forward svc/argo-server" || true
	kubectl wait --for=condition=ready pod -l app=argo-server -n argo --timeout=180s
	kubectl wait --for=condition=ready pod -l eventsource-name=webhook -n argo-events --timeout=180s
	kubectl wait --for=condition=ready pod -l sensor-name=webhook -n argo-events --timeout=180s
	kubectl port-forward svc/webhook-eventsource-svc 12000:12000 -n argo-events &
	kubectl port-forward svc/argo-server 2746:2746 -n argo &
	@echo "Waiting for port-forwards to bind..."
	@until nc -z localhost 12000; do sleep 1; done
	@until nc -z localhost 2746; do sleep 1; done
	@echo "Ports ready."

run-test: port-forwarding
	curl -s -w "\nHTTP Status: %{http_code}\n" \
		-d '{"message":"hello"}' \
		-H "Content-Type: application/json" \
		-X POST http://localhost:12000/push
	@echo "Waiting for workflow to appear..."
	@sleep 3
	kubectl get workflows -n argo-workflows

deploy-jaeger: namespaces
	kubectl apply -f platform-observability/k8s/jaeger.yaml

deploy-prometheus: namespaces
	kubectl apply -f platform-observability/k8s/prometheus-config.yaml
	kubectl apply -f platform-observability/k8s/prometheus.yaml

deploy-grafana: namespaces
	kubectl apply -f platform-observability/k8s/grafana.yaml

deploy-otel: deploy-jaeger deploy-prometheus deploy-grafana
	kubectl apply -f platform-observability/k8s/otel-collector-config.yaml
	kubectl apply -f platform-observability/k8s/otel-collector.yaml

verify: deploy-otel
	kubectl wait --for=condition=ready pod -l app=jaeger -n monitoring --timeout=120s
	kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s
	kubectl get pods -n monitoring

# -----------------------------------------
# KARGO
# -----------------------------------------
kargo-install: namespaces
	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
	@echo "Waiting for cert-manager..."
	kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=120s
	@echo "Install Kargo with: helm install kargo oci://ghcr.io/akuity/kargo-charts/kargo --namespace kargo --create-namespace --set api.adminAccount.passwordHash=<hash> --set api.adminAccount.tokenSigningKey=changeme --set controller.argocd.integrationEnabled=false"

kargo-login:
	kubectl port-forward --namespace kargo svc/kargo-api 3100:443 &
	kargo login https://localhost:3100 --admin --insecure-skip-tls-verify

kargo-setup: kargo-login
	kubectl apply -f gitops-infra-pipeline/kargo/project.yaml
	kubectl apply -f gitops-infra-pipeline/kargo/warehouse.yaml
	kubectl apply -f gitops-infra-pipeline/kargo/stages.yaml

kargo-promote-dev:
	@echo "Usage: make kargo-promote-dev FREIGHT=<hash>"
	kargo promote --project gitops-infra --freight $(FREIGHT) --stage dev

kargo-promote-prod:
	@echo "Usage: make kargo-promote-prod FREIGHT=<hash>"
	kargo promote --project gitops-infra --freight $(FREIGHT) --stage prod

# -----------------------------------------
# TERRAFORM
# -----------------------------------------
tf-bootstrap:
	aws s3api create-bucket --bucket YOUR-TFSTATE-BUCKET-NAME --region us-east-1
	aws s3api put-bucket-versioning --bucket YOUR-TFSTATE-BUCKET-NAME \
		--versioning-configuration Status=Enabled
	aws dynamodb create-table --table-name YOUR-TFLOCK-TABLE-NAME \
		--attribute-definitions AttributeName=LockID,AttributeType=S \
		--key-schema AttributeName=LockID,KeyType=HASH \
		--billing-mode PAY_PER_REQUEST

tf-init: clone
	cd gitops-infra-pipeline/terraform/aws/dev && terraform init -backend=false
	cd gitops-infra-pipeline/terraform/aws/prod && terraform init -backend=false
	cd gitops-infra-pipeline/terraform/gcp && terraform init
	cd gitops-infra-pipeline/terraform/azure && terraform init

tf-policy: tf-init
	cd gitops-infra-pipeline/terraform/aws/dev && terraform plan -out=tfplan.binary && terraform show -json tfplan.binary > tfplan.json
	conftest test gitops-infra-pipeline/terraform/aws/dev/tfplan.json --policy gitops-infra-pipeline/policy --namespace terraform.policies
	cd gitops-infra-pipeline/terraform/gcp && terraform plan -out=tfplan.binary && terraform show -json tfplan.binary > tfplan.json
	conftest test gitops-infra-pipeline/terraform/gcp/tfplan.json --policy gitops-infra-pipeline/policy --namespace terraform.policies

tf-validate: tf-init
	cd gitops-infra-pipeline/terraform/aws/dev && terraform fmt -check -recursive && terraform validate
	cd gitops-infra-pipeline/terraform/aws/prod && terraform fmt -check -recursive && terraform validate
	cd gitops-infra-pipeline/terraform/gcp && terraform fmt -check -recursive && terraform validate
	cd gitops-infra-pipeline/terraform/azure && terraform fmt -check -recursive && terraform validate

tf-scan: tf-validate
	trivy config gitops-infra-pipeline/terraform/aws/dev --severity HIGH,CRITICAL
	trivy config gitops-infra-pipeline/terraform/aws/prod --severity HIGH,CRITICAL
	trivy config gitops-infra-pipeline/terraform/gcp --severity HIGH,CRITICAL
	trivy config gitops-infra-pipeline/terraform/azure --severity HIGH,CRITICAL

platform-up: check-prereqs operator-install verify pull-tiny-llama-model run-test


# -----------------------------------------
# TEARDOWN
# -----------------------------------------
teardown:
	pkill -f "port-forward" || true
	kind delete cluster --name $(CLUSTER_NAME)
	rm -rf argo-event-pipeline gitops-infra-pipeline platform-observability namespace-provisioner
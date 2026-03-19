CLUSTER_NAME = my-cluster

.PHONY:  check-prereqs cluster-create namespaces clone argo-install argo-event-install apply-rbac deploy-manifest pull-tiny-llama-model port-forwarding run-test deploy-jaeger deploy-prometheus deploy-grafana deploy-otel verify tf-init tf-policy tf-validate tf-scan platform-up

clone:
	git clone https://github.com/SmartBrisco/argo-event-pipeline || true
	git clone https://github.com/SmartBrisco/gitops-infra-pipeline || true
	git clone https://github.com/SmartBrisco/platform-observability || true

check-prereqs:
	@echo "Checking required tools..."
	@command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found. Install: https://kubernetes.io/docs/tasks/tools/"; exit 1; }
	@command -v kind >/dev/null 2>&1 || { echo "kind not found. Install: https://kind.sigs.k8s.io/docs/user/quick-start/"; exit 1; }
	@command -v argo >/dev/null 2>&1 || { echo "argo CLI not found. Install: https://argo-workflows.readthedocs.io/en/latest/walk-through/argo-cli/"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "terraform not found. Install: https://developer.hashicorp.com/terraform/install"; exit 1; }
	@command -v trivy >/dev/null 2>&1 || { echo "trivy not found. Install: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"; exit 1; }
	@command -v conftest >/dev/null 2>&1 || { echo "conftest not found. Install: https://www.conftest.dev/install/"; exit 1; }
	@echo "All prerequisites satisfied."


cluster-create:clone 
	kind create cluster --name $(CLUSTER_NAME)

namespaces: cluster-create
	kubectl create namespace argo
	kubectl create namespace argo-events
	kubectl create namespace argo-workflows
	kubectl create namespace monitoring

argo-install: namespaces		
	kubectl apply --server-side -f https://github.com/argoproj/argo-workflows/releases/latest/download/quick-start-minimal.yaml

argo-event-install: namespaces 
	kubectl apply -n argo-events -f https://github.com/argoproj/argo-events/releases/latest/download/install.yaml
	kubectl apply -n argo-events -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml

apply-rbac: argo-install argo-event-install
	kubectl apply -f argo-event-pipeline/rbac/clusterrole.yaml
	kubectl apply -f argo-event-pipeline/rbac/clusterrolebinding.yaml

deploy-manifest: apply-rbac
	kubectl apply -f argo-event-pipeline/manifest/eventsource-webhook.yaml
	kubectl apply -f argo-event-pipeline/manifest/eventsource-svc.yaml
	kubectl apply -f argo-event-pipeline/manifest/ollama-deployment.yaml
	kubectl apply -f argo-event-pipeline/manifest/sensor-webhook.yaml

pull-tiny-llama-model: deploy-manifest
	kubectl exec -n argo-workflows deployment/ollama -- ollama pull tinyllama

port-forwarding: deploy-manifest
	kubectl port-forward svc/webhook-eventsource-svc 12000:12000 -n argo-events &
	kubectl port-forward svc/argo-server 2746:2746 -n argo &
  
run-test: port-forwarding
	sleep 5
	curl -d '{"message":"hello"}' -H "Content-Type: application/json" -X POST http://localhost:12000/push
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
	sleep 5 
	kubectl get pods -n monitoring

tf-init: clone
	cd gitops-infra-pipeline/terraform/aws && terraform init
	cd gitops-infra-pipeline/terraform/gcp && terraform init
	cd gitops-infra-pipeline/terraform/azure && terraform init

tf-policy: tf-init
	cd gitops-infra-pipeline/terraform/aws && terraform plan -out=tfplan.binary && terraform show -json tfplan.binary > tfplan.json
	conftest test gitops-infra-pipeline/terraform/aws/tfplan.json --policy gitops-infra-pipeline/policy --namespace terraform.policies
	cd gitops-infra-pipeline/terraform/gcp && terraform plan -out=tfplan.binary && terraform show -json tfplan.binary > tfplan.json
	conftest test gitops-infra-pipeline/terraform/gcp/tfplan.json --policy gitops-infra-pipeline/policy --namespace terraform.policies

tf-validate: tf-init
	cd gitops-infra-pipeline/terraform/aws && terraform fmt -check -recursive && terraform validate
	cd gitops-infra-pipeline/terraform/gcp && terraform fmt -check -recursive && terraform validate
	cd gitops-infra-pipeline/terraform/azure && terraform fmt -check -recursive && terraform validate

tf-scan: tf-validate
	trivy config gitops-infra-pipeline/terraform/aws --severity HIGH,CRITICAL
	trivy config gitops-infra-pipeline/terraform/gcp --severity HIGH,CRITICAL
	trivy config gitops-infra-pipeline/terraform/azure --severity HIGH,CRITICAL

platform-up: check-prereqs verify run-test pull-tiny-llama-model

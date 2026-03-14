CLUSTER_NAME = my-cluster

.PHONY: cluster-create namespaces clone argo-install argo-event-install apply-rbac deploy-manifest pull-tiny-llama-model port-forwarding run-test 

clone:
	git clone https://github.com/SmartBrisco/argo-event-pipeline || true
	git clone https://github.com/SmartBrisco/gitops-infra-pipeline || true
	git clone https://github.com/SmartBrisco/platform-observability || true

cluster-create:clone 
	kind create cluster --name $(CLUSTER_NAME)

namespaces: cluster-create
	kubectl create namespace argo
	kubectl create namespace argo-events
	kubectl create namespace argo-workflows

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
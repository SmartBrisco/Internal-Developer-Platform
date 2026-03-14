CLUSTER_NAME = my-cluster

.PHONY: cluster-create namespaces clone argo-install 

clone:
	git clone https://github.com/SmartBrisco/argo-event-pipeline
	git clone https://github.com/SmartBrisco/gitops-infra-pipeline
	git clone https://github.com/SmartBrisco/platform-observability

cluster-create:clone 
	kind create cluster --name $(CLUSTER_NAME)

namespaces:
	kubectl create namespace argo
	kubectl create namespace argo-events
	kubectl create namespace argo-workflows

argo-install:		
	kubectl apply --server-side -f https://github.com/argoproj/argo-workflows/releases/latest/download/quick-start-minimal.yaml

argo-event-install:
	kubectl apply -n argo-events -f https://github.com/argoproj/argo-events/releases/latest/download/install.yaml
	kubectl apply -n argo-events -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml



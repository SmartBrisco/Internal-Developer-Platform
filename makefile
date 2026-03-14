CLUSTER_NAME = my-cluster

.PHONY: cluster-create clone 

clone:
	git clone https://github.com/SmartBrisco/argo-event-pipeline
	git clone https://github.com/SmartBrisco/gitops-infra-pipeline
	git clone https://github.com/SmartBrisco/platform-observability

cluster-create:clone 
	kind create cluster --name $(CLUSTER_NAME)


.PHONY: init plan apply up kubeconfig stop start destroy whoami fmt validate

PROFILE := default
REGION  := us-west-2
CLUSTER := infra-sandbox
GPU_NG  := infra-sandbox-gpu
TG_DIR  := terragrunt/sandbox

# `make up` = apply the stack (one root: vpc + eks + GPU stack + vllm), then write kubeconfig.
# vLLM converges ~8-10 min after this returns (image pull + model load; helm wait=false).
up: apply kubeconfig

whoami:
	aws sts get-caller-identity --profile $(PROFILE)

init:
	cd $(TG_DIR) && terragrunt init --backend-bootstrap --non-interactive

fmt:
	cd terragrunt && terragrunt hcl format

validate:
	cd $(TG_DIR) && terragrunt validate --non-interactive

plan:
	cd $(TG_DIR) && terragrunt plan --non-interactive

apply:
	cd $(TG_DIR) && terragrunt apply --non-interactive

kubeconfig:
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION) --profile $(PROFILE)

# stop/start change the GPU node group scaling out-of-band via the AWS API.
# desired_size is ignore_changes in eks_nodes.tf, so `make apply` will NOT revert a
# stop/start (nor restart a stopped node); it only resets min_size to 0 (harmless).
stop:
	aws eks update-nodegroup-config --cluster-name $(CLUSTER) --nodegroup-name $(GPU_NG) \
	  --scaling-config minSize=0,maxSize=2,desiredSize=0 \
	  --region $(REGION) --profile $(PROFILE)

start:
	aws eks update-nodegroup-config --cluster-name $(CLUSTER) --nodegroup-name $(GPU_NG) \
	  --scaling-config minSize=1,maxSize=2,desiredSize=1 \
	  --region $(REGION) --profile $(PROFILE)

destroy:
	cd $(TG_DIR) && terragrunt destroy --non-interactive

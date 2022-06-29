.PHONY: help awspec-init fmt tests validate destroy-test apply-test validation integration clean-docker pull-docker
.DEFAULT_GOAL := help

SHORT_GITHASH := $(shell git rev-parse --short HEAD)
REGISTRY := autodesk-docker.art-bobcat.autodesk.com
IMAGE := dacloud-tf-build-tools:master
ROOTDIR := /opt/plangrid/app/tf_module
TG_CMD = terragrunt $(CMD) --terragrunt-source $(ROOTDIR) --terragrunt-config $(ROOTDIR)/test/integration/testing.hcl --terragrunt-ignore-external-dependencies \
	--terragrunt-parallelism 6
TG_RUN := docker run -it --rm \
	-e AWS_PROFILE \
    -e AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY \
    -v ~/.aws:/root/.aws:ro \
    -v ~/.ssh:/root/.ssh:ro \
	-v $(CURDIR):$(ROOTDIR)
TG_TEST := $(TG_RUN) -w $(ROOTDIR) $(REGISTRY)/$(IMAGE)
TG_SUITE := $(TG_RUN) $(REGISTRY)/$(IMAGE)

# This help function will automatically generate help/usage text for any make target that is commented with "##".
# Targets with a singe "#" description do not show up in the help text
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-40s\033[0m %s\n", $$1, $$2}'



init: generate-versions-tf  ## inits the terraform env for this module. Used by validate and fmt
	terraform init -backend=False

validate: init ## Runs terragrunt validate
	terraform validate

fmt: init ## Formats terraform for lint/static checking purposes
	terraform fmt -check=true -diff=true -recursive

pull-docker:  ## Pulls down an update to date version of the test suite image
	docker pull $(REGISTRY)/$(IMAGE)

clean-docker:  ## Removes any left over exited containers and test suite image
	-docker rm $(docker ps -a -f status=exited -f ancestor=$(IMAGE) -q)
	-docker rmi $(REGISTRY)/$(IMAGE)

# OSX ships with make 3.8.1, which does not support ONESHELL, which is why this target is one big statement.
## This is useful in local testing when doing terraform init and terraform validate
generate-versions-tf: $(eval SHELL:=/bin/bash) ## Generates a versions.tf file from the master branch of dacloud-terraform. 
	@[[ -f versions.tf ]] && echo "versions.tf already exists, skipping. Remove versions.tf locally to regenerate" || (tmp_dir=$$(mktemp -d -t ci-XXXXXXXXXX) && \
	echo "Working in $$tmp_dir" && \
	git clone --depth 1 git@github.com:plangrid/dacloud-terraform.git $$tmp_dir/dacloud-terraform && \
	cat $$tmp_dir/dacloud-terraform/aws/723151894364/terragrunt.hcl | \
	awk 'BEGIN{found=0;}/## START PROVIDER/{if(!found){found=1;$$0=substr($$0,index($$0, "## START PROVIDER")+3);}}/## END PROVIDER/{if(found){found=2;$$0=substr($$0,0,index($$0,"## END PROVIDER")-1);}}{ if(found){print;if(found==2)found=0;}}' | \
	awk 'BEGIN{found=0;}/EOF/{if(!found){found=1;$$0=substr($$0,index($$0, "EOF")+3);}}/EOF/{if(found){found=2;$$0=substr($$0,0,index($$0,"EOF")-1);}}{ if(found){print;if(found==2)found=0;}}' > versions.tf && \
	echo "versions.tf written" && \
	rm -rf $tmp_dir)

terraform-clean: ## Removes terragrunt cache and .terraform files
	-rm -rf .terraform
	-rm -rf .terragrunt_cache
	-rm -rf .terraform.lock.hcl
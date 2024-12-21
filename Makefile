SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -O extglob -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

.DEFAULT_GOAL := help
VERSION := $(shell cat ./VERSION)
COMMIT_HASH := $(shell git log -1 --pretty=format:"sha-%h")
PLATFORMS := "linux/arm/v7,linux/arm64/v8,linux/amd64"

BUILD_FLAGS ?=

ifndef HOMELAB_OP_SERVICE_ACCOUNT_TOKEN
$(error HOMELAB_OP_SERVICE_ACCOUNT_TOKEN is not set in your environment)
endif

.PHONY: help
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' Makefile

.PHONY: setup
setup: dotenv	## Setup the build environment

.PHONY: dotenv
dotenv: .env	## Setup build secrets in .env files

.env: .env.template
	OP_SERVICE_ACCOUNT_TOKEN=${HOMELAB_OP_SERVICE_ACCOUNT_TOKEN} op inject --force --in-file $< --out-file $@

# Wrap the build in a check for an existing .env file
ifeq ($(shell test -f .env; echo $$?), 0)
include .env
ENVVARS := $(shell sed -ne 's/ *\#.*$$//; /./ s/=.*$$// p' .env )
$(foreach var,$(ENVVARS),$(eval $(shell echo export $(var)="$($(var))")))

WIREGUARD_CLIENT := wireguard-client
WIREGUARD_CLIENT_REPO := ${GITHUB_REGISTRY}/$(GITHUB_USER)
WIREGUARD_CLIENT_IMAGE := $(WIREGUARD_CLIENT)
WIREGUARD_CLIENT_DOCKERFILE := ./docker/$(WIREGUARD_CLIENT)/Dockerfile

DOCKER_BUILDER := $(WIREGUARD_CLIENT)-builder

HADOLINT_IMAGE := hadolint/hadolint

.PHONY: lint
lint: lint_docker	## Run all linters on the code base

.PHONY: lint_docker
lint_docker: lint_compose lint_dockerfiles ## Lint all Docker related files

.PHONY: lint_compose
lint_compose:	## Lint docker-compose.yml
	docker compose -f docker-compose.yml config 1> /dev/null

.PHONY: lint_dockerfiles
lint_dockerfiles: _lint_dockerfiles ## Lint all Dockerfiles

.PHONY: _lint_dockerfiles
_lint_dockerfiles: lint_$(WIREGUARD_CLIENT)_dockerfile

.PHONY: lint_$(WIREGUARD_CLIENT)_dockerfile
lint_$(WIREGUARD_CLIENT)_dockerfile:
	$(MAKE) _lint_dockerfile -e BUILD_DOCKERFILE="$(WIREGUARD_CLIENT_DOCKERFILE)"

BUILD_TARGETS := build_wireguard_client

.PHONY: build
build: $(BUILD_TARGETS) ## Build all images

REBUILD_TARGETS := rebuild_wireguard_client

.PHONY: rebuild
rebuild: $(REBUILD_TARGETS) ## Rebuild all images (no cache)

RELEASE_TARGETS := release_wireguard_client

.PHONY: release
release: $(RELEASE_TARGETS)	## Tag and push all images

build_wireguard_client:	## Build the Docker image
	$(MAKE) _build_image \
		-e BUILD_DOCKERFILE=./docker/$(WIREGUARD_CLIENT)/Dockerfile \
		-e BUILD_REPO=$(WIREGUARD_CLIENT_REPO) \
		-e BUILD_IMAGE=$(WIREGUARD_CLIENT_IMAGE) \
		-e BUILD_FLAGS="--build-arg VERSION=${VERSION}"

rebuild_wireguard_client:	## Rebuild the Docker image (no cache)
	$(MAKE) _build_image \
		-e BUILD_DOCKERFILE=./docker/$(WIREGUARD_CLIENT)/Dockerfile \
		-e BUILD_REPO=$(WIREGUARD_CLIENT_REPO) \
		-e BUILD_IMAGE=$(WIREGUARD_CLIENT_IMAGE) \
		-e BUILD_FLAGS="--no-cache --build-arg VERSION=${VERSION}"

release_wireguard_client: build_wireguard_client	## Tag and push Docker image
	$(MAKE) _tag_image \
		-e BUILD_REPO=$(WIREGUARD_CLIENT_REPO) \
		-e BUILD_IMAGE=$(WIREGUARD_CLIENT_IMAGE) \
		-e BUILD_TAG=$(COMMIT_HASH)
	$(MAKE) _tag_image \
		-e BUILD_REPO=$(WIREGUARD_CLIENT_REPO) \
		-e BUILD_IMAGE=$(WIREGUARD_CLIENT_IMAGE) \
		-e BUILD_TAG=$(VERSION)

.PHONY: repo_login
repo_login:	## Login to GHCR
	echo "${GITHUB_PAT}" | docker login ${GITHUB_REGISTRY} -u ${GITHUB_USER} --password-stdin

.PHONY: up
up: repo_login	## Bring the API container stack up
	docker compose --env-file .env up -d

.PHONY: down
down:	## Bring the API container stack down
	docker compose --env-file .env down

.PHONY: pull
pull:	## Pull all current Docker images
	docker compose --env-file .env pull

.PHONY: restart
restart: down up	## Restart the API container stack

.PHONY: destroy
destroy:	## Stop and clean up the API container stack
	docker compose --env-file ./${DOCKER_DIR}/.env -f ${DOCKER_DIR}/docker-compose.yml down -v

# Private (hidden) build targets ...

.PHONY: _lint_dockerfile
_lint_dockerfile:
	docker run --rm -i -e HADOLINT_IGNORE=DL3008,SC2174 ${HADOLINT_IMAGE} < ${BUILD_DOCKERFILE}

.PHONY: _init_builder
init_builder:
	docker buildx inspect $(DOCKER_BUILDER) > /dev/null 2>&1 || \
		docker buildx create --name $(DOCKER_BUILDER) --bootstrap --use

.PHONY: _build_image
_build_image: repo_login _init_builder
	docker buildx build --platform=$(PLATFORMS) \
		--file ${BUILD_DOCKERFILE} \
		--push \
		--tag ${BUILD_REPO}/${BUILD_IMAGE}:latest \
		--provenance=false \
		--ssh default \
		--build-arg VERSION=${VERSION} \
		${BUILD_FLAGS} .

.PHONY: _tag_image
_tag_image: repo_login
	docker buildx imagetools create ${BUILD_REPO}/$(BUILD_IMAGE):latest \
		--tag ${BUILD_REPO}/$(BUILD_IMAGE):$(BUILD_TAG)

# No .env file; fail the build
else
.DEFAULT:
	$(error Cannot find a .env file; run "make dotenv" first)
endif

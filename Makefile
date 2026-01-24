.PHONY: build run test docker-build docker-run docker-push clean release docker-buildx docker-buildx-push docker-buildx-setup docker-validate docker-regression-test

APP_NAME = malachimq
DOCKER_USERNAME ?= hectorcardoso
VERSION ?= $(shell grep '@version' mix.exs | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
PLATFORMS ?= linux/amd64,linux/arm64

build:
	mix deps.get
	mix compile

run:
	mix run --no-halt

test:
	mix test

release:
	MIX_ENV=prod mix deps.get
	MIX_ENV=prod mix release

docker-build:
	docker build -t $(DOCKER_USERNAME)/$(APP_NAME):$(VERSION) .
	docker tag $(DOCKER_USERNAME)/$(APP_NAME):$(VERSION) $(DOCKER_USERNAME)/$(APP_NAME):latest

docker-buildx-setup:
	@echo "Setting up Docker Buildx..."
	docker buildx create --name $(APP_NAME)-builder --use --bootstrap || docker buildx use $(APP_NAME)-builder
	docker buildx inspect --bootstrap

docker-buildx:
	@echo "Building multi-platform Docker image ($(PLATFORMS))..."
	docker buildx build \
		--platform $(PLATFORMS) \
		-t $(DOCKER_USERNAME)/$(APP_NAME):$(VERSION) \
		-t $(DOCKER_USERNAME)/$(APP_NAME):latest \
		--load \
		.

docker-buildx-push:
	@echo "Building and pushing multi-platform Docker image ($(PLATFORMS))..."
	docker buildx build \
		--platform $(PLATFORMS) \
		-t $(DOCKER_USERNAME)/$(APP_NAME):$(VERSION) \
		-t $(DOCKER_USERNAME)/$(APP_NAME):latest \
		--push \
		.

docker-run:
	docker run \
		--name $(APP_NAME) \
		-p 4040:4040 \
		-p 4041:4041 \
		$(DOCKER_USERNAME)/$(APP_NAME):$(VERSION)

docker-stop:
	docker stop $(APP_NAME) || true
	docker rm $(APP_NAME) || true

docker-push:
	docker push $(DOCKER_USERNAME)/$(APP_NAME):$(VERSION)
	docker push $(DOCKER_USERNAME)/$(APP_NAME):latest

docker-logs:
	docker logs -f $(APP_NAME)

compose-up:
	docker-compose up -d

compose-down:
	docker-compose down

compose-logs:
	docker-compose logs -f

compose-producer:
	docker-compose --profile tools run --rm producer

docker-validate:
	@echo "Running Docker build validation..."
	./scripts/validate-docker-build.sh

docker-regression-test:
	@echo "Running Docker regression tests..."
	./scripts/docker-regression-test.sh $(DOCKER_USERNAME)/$(APP_NAME):$(VERSION)

docker-test-all: docker-build docker-validate docker-regression-test
	@echo "All Docker tests completed successfully!"

clean:
	rm -rf _build deps
	docker rmi $(DOCKER_USERNAME)/$(APP_NAME):$(VERSION) || true
	docker rmi $(DOCKER_USERNAME)/$(APP_NAME):latest || true

all: build test docker-build

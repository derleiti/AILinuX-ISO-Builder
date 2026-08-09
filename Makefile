.PHONY: build create clean preflight validate smoke

build:
	./scripts/build.sh

create:
	./create.sh

clean:
	sudo lb clean --purge

preflight:
	./scripts/preflight-build.sh rootless

validate:
	./scripts/validate-project.sh

smoke:
	./scripts/smoke-test-iso.sh

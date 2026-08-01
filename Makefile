.PHONY: build create clean validate smoke

build:
	./scripts/build.sh

create:
	./create.sh

clean:
	sudo lb clean --purge

validate:
	./scripts/validate-project.sh

smoke:
	./scripts/smoke-test-iso.sh

# makefile is used to make :make command in vim work out of the box
.PHONY: \
	build-debug.sh \
	test.sh \
	swift-test.sh \
	format.sh \
	lint.sh

build-debug.sh:
	./script/build-debug.sh

test.sh:
	./script/test.sh

swift-test.sh:
	./script/swift-test.sh

format.sh:
	./script/format.sh

lint.sh:
	./script/lint.sh

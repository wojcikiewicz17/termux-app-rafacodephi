.PHONY: all build link verify run clean
all: build verify
build:
	bash build_linear.sh
link: build
	bash link_linear.sh
verify:
	bash verify_linear.sh
run: link
	./build/raf_linear_panel
clean:
	rm -rf build reports
	mkdir -p build reports

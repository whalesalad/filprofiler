.SHELLFLAGS := -eu -o pipefail -c
SHELL := bash
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

.PHONY: build
build: target/release/libpymemprofile_api.a
	pip install -e .
	rm -rf build/
	python setup.py build_ext --inplace
	python setup.py install_data

# Only necessary for benchmarks, only works with Python 3.8 for now.
venv/bin/_fil-python: filprofiler/*.c target/release/libpymemprofile_api.a
	gcc -std=c11 $(shell python3.8-config --cflags) -export-dynamic -flto -o $@ $^ -lpython3.8 $(shell python3.8-config --ldflags)

target/release/libpymemprofile_api.a: Cargo.lock memapi/Cargo.toml memapi/src/*.rs
	cargo build --release

venv:
	python3 -m venv venv/

.PHONY: test
test:
	make test-rust
	make test-python

.PHONY: test-rust
test-rust:
	env RUST_BACKTRACE=1 cargo test

.PHONY: test-python
test-python: build
	make test-python-no-deps
	env RUST_BACKTRACE=1 py.test filprofiler/tests/

.PHONY: test-python-no-deps
test-python-no-deps:
	cythonize -3 -i tests/test-scripts/pymalloc.pyx
	c++ -shared -fPIC -lpthread tests/test-scripts/cpp.cpp -o tests/test-scripts/cpp.so
	cc -shared -fPIC -lpthread tests/test-scripts/malloc_on_thread_exit.c -o tests/test-scripts/malloc_on_thread_exit.so
	cd tests/test-scripts && python -m numpy.f2py -c fortran.f90 -m fortran
	env RUST_BACKTRACE=1 py.test tests/

.PHONY: docker-image
docker-image:
	docker build -t manylinux-rust -f wheels/Dockerfile.build .

.PHONY: wheel
wheel:
	python setup.py bdist_wheel

.PHONY: manylinux-wheel
manylinux-wheel:
	docker run -u $(shell id -u):$(shell id -g) -v $(PWD):/src quay.io/pypa/manylinux2010_x86_64:latest /src/wheels/build-wheels.sh

.PHONY: clean
clean:
	rm -f filprofiler/_fil-python
	rm -rf target
	rm -rf filprofiler/*.so
	rm -rf filprofiler/*.dylib
	python setup.py clean

.PHONY: licenses
licenses:
	cd memapi && cargo lichking check
	cd memapi && cargo lichking bundle --file ../filprofiler/licenses.txt || true
	cat extra-licenses/APSL.txt >> filprofiler/licenses.txt

data_kernelspec/kernel.json: generate-kernelspec.py
	rm -rf data_kernelspec
	python generate-kernelspec.py

.PHONY: benchmark
benchmark: benchmarks/results/*.json
	python setup.py --version > benchmarks/results/version.txt
	git diff --word-diff benchmarks/results/

.PHONY: benchmarks/results/pystone.json
benchmarks/results/pystone.json: build venv/bin/_fil-python
	FIL_NO_REPORT=1 FIL_BENCHMARK=benchmarks/results/pystone.json fil-profile run benchmarks/pystone.py

.PHONY: benchmarks/results/image-translate.json
benchmarks/results/image-translate.json: build venv/bin/_fil-python
	pip install --upgrade scikit-image==0.16.2 PyWavelets==1.1.1 scipy==1.4.1 numpy==1.18.0 imageio==2.6.1
	FIL_NO_REPORT=1 FIL_BENCHMARK=benchmarks/results/image-translate.json fil-profile run benchmarks/image-translate.py 2

.PHONY: benchmarks/results/multithreading-1.json
benchmarks/results/multithreading-1.json: build venv/bin/_fil-python
	cythonize -3 -i benchmarks/pymalloc.pyx
	FIL_NO_REPORT=1 FIL_BENCHMARK=benchmarks/results/multithreading-1.json fil-profile run benchmarks/multithreading.py 1

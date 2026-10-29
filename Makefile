# Makefile
.PHONY: build test

build:
	docker build -t ngx-stream-test .

test:
	docker run --rm ngx-stream-test

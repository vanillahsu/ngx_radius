# NGX Radius Project

This project contains a Lua-based `Dictionary` class and related tests.

## Prerequisites

- Docker

## How to Run Tests

You can run the tests using `make` or via `docker` commands directly.

### Using Makefile

1. **Build the Docker image:**
   ```bash
   make build
   ```

2. **Run the tests:**
   ```bash
   make test
   ```

### Using Docker directly

1. **Build the image:**
   ```bash
   docker build -t ngx-radius-test .
   ```

2. **Run the container:**
   ```bash
   docker run --rm ngx-radius-test
   ```

## Project Structure

- `dictionary`: Large data file (Source of truth).
- `dictionary.lua`: The Lua module for managing the dictionary. **Optimized with `ngx.re` and LuaJIT pattern.**
- `dictionary_test.lua`: Test suite for the `Dictionary` class.
- `nginx.conf`: Nginx configuration for stream processing.
- `test_stream.t`: Perl test suite for Nginx stream testing.

.PHONY: test lint format setup schedules clean

# Run the test suite
test:
	python3 -m pytest tests/ -v

# Lint Python files (check only)
lint:
	ruff check .
	ruff format --check .

# Lint and auto-fix Python files
format:
	ruff check --fix .
	ruff format .

# Install dev dependencies and run project setup
setup:
	pip3 install -e ".[dev]"
	./scripts/setup.sh

# Install/update cron schedules
schedules:
	./scripts/sync-schedules.sh

# Clean up generated/temporary files
clean:
	rm -f .run.lock

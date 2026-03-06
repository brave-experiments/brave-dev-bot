.PHONY: test lint format setup schedules view-schedules clean archive archive-progress archive-prd

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
	@if command -v uv >/dev/null 2>&1; then \
		uv pip install pytest ruff; \
	elif command -v pip3 >/dev/null 2>&1; then \
		pip3 install pytest ruff; \
	else \
		echo "Error: Neither uv nor pip3 found. Install uv (https://docs.astral.sh/uv/) or pip3."; exit 1; \
	fi
	@rm -rf *.egg-info
	./scripts/setup.sh

# Install/update cron schedules
schedules:
	./scripts/sync-schedules.sh

# Show schedule summary
view-schedules:
	./scripts/view-schedules.sh

# Archive progress.txt (append to progress.archived.txt, reset progress.txt)
archive-progress:
	@if [ ! -f data/progress.txt ]; then echo "No progress.txt to archive."; exit 0; fi
	@echo "Archiving progress.txt..."
	@cat data/progress.txt >> data/progress.archived.txt
	@echo "" >> data/progress.archived.txt
	@echo "# Progress Log" > data/progress.txt
	@echo "Started: $$(date)" >> data/progress.txt
	@echo "---" >> data/progress.txt
	@echo "Archived $$(wc -l < data/progress.archived.txt) lines to progress.archived.txt"

# Archive completed PRD stories (merged/invalid → prd.archived.json)
archive-prd:
	python3 scripts/archive-prd.py data/prd.json

# Archive both progress.txt and completed PRD stories
archive: archive-progress archive-prd

# Clean up generated/temporary files
clean:
	rm -f .run.lock

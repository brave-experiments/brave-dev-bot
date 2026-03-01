.PHONY: run test lint format

# Run the agent loop
# Usage:
#   make run                          # 10 iterations, print mode
#   make run ARGS="1 tui"             # 1 iteration, TUI mode
#   make run ARGS="1 tui fix the bug" # 1 iteration, TUI mode, extra instructions
run:
	./run.sh $(ARGS)

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

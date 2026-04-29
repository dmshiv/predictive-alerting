# =============================================================================
# WHAT  : Shortcuts for common project actions.
# WHY   : So you do not have to remember every script path.
# HOW   : Run `make help` to see all commands.
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# --- Lifecycle ---------------------------------------------------------------
bootstrap:  ## One-time: create the Terraform state bucket (run before deploy)
	./scripts/bootstrap.sh

deploy:  ## Build the entire cloud infra (one command)
	./scripts/start.sh

destroy:  ## Pause compute (cheap, keeps data)
	./scripts/stop.sh

nuke:  ## FULL teardown - destroys all 19 folders in reverse, deletes data
	./scripts/destroy.sh

smoke:  ## Run post-deploy sanity checks
	./scripts/smoke_test.sh

# --- Demo --------------------------------------------------------------------
demo-drift:  ## Trigger drift demo (run demo-reset to stop)
	python scripts/chaos_inject.py --mode=drift

demo-latency:  ## Trigger latency spike demo
	python scripts/chaos_inject.py --mode=latency

demo-burst:  ## Trigger traffic burst demo
	python scripts/chaos_inject.py --mode=burst

demo-reset:  ## Reset traffic generator to baseline
	python scripts/chaos_inject.py --mode=baseline

demo-off:  ## Pause the load generator (zero traffic)
	python scripts/chaos_inject.py --mode=off

# --- Local dev ---------------------------------------------------------------
install:  ## Install Python deps in a venv
	python -m venv .venv && \
	.venv/bin/pip install --upgrade pip && \
	.venv/bin/pip install -r requirements.txt

test:  ## Run the pytest suite
	.venv/bin/pytest -v tests/

lint:  ## Lint and format
	.venv/bin/ruff check src/ scripts/ tests/
	.venv/bin/black --check src/ scripts/ tests/

format:  ## Auto-format
	.venv/bin/black src/ scripts/ tests/
	.venv/bin/ruff check --fix src/ scripts/ tests/

# --- Optional setup ----------------------------------------------------------
setup-slack:  ## One-time: store Slack webhook in Secret Manager
	./scripts/setup_slack.sh

setup-email:  ## Create Cloud Monitoring email notification channel
	./scripts/setup_email.sh

.PHONY: help bootstrap deploy destroy nuke smoke demo-drift demo-latency demo-burst demo-reset demo-off install test lint format setup-slack setup-email

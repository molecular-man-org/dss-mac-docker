SHELL := /bin/bash
SKILLS_DIR := $(HOME)/.claude/skills
REPO := $(shell pwd)

.PHONY: help install uninstall test lint

help: ## Show available targets
	@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST) | \
		awk -F':.*##' '{printf "  %-12s %s\n", $$1, $$2}'

# Skills are COPIED, not symlinked, and the CLI path is substituted in. That
# sidesteps any question of whether Claude Code follows symlinks under
# ~/.claude/skills, and guarantees the path is right even if the repo moves.
# Re-run `make install` after editing anything under skills/.
install: ## Install skills into ~/.claude/skills (copies; re-run after edits)
	@mkdir -p "$(SKILLS_DIR)"
	@for s in $(REPO)/skills/*/; do \
		[ -e "$$s/SKILL.md" ] || continue; \
		n=$$(basename "$$s"); \
		rm -rf "$(SKILLS_DIR)/$$n"; \
		mkdir -p "$(SKILLS_DIR)/$$n"; \
		sed 's|__DSS_LAB__|$(REPO)/bin/dss-lab|g' "$$s/SKILL.md" > "$(SKILLS_DIR)/$$n/SKILL.md"; \
		echo "installed $$n"; \
	done
	@echo "CLI path: $(REPO)/bin/dss-lab"

uninstall: ## Remove the installed skills
	@for s in $(REPO)/skills/*/; do \
		n=$$(basename "$$s"); \
		if [ -e "$(SKILLS_DIR)/$$n" ] || [ -L "$(SKILLS_DIR)/$$n" ]; then \
			rm -rf "$(SKILLS_DIR)/$$n"; echo "removed $$n"; \
		fi; \
	done; true

test: ## Run unit tests
	@bash tests/run_tests.sh

lint: ## Lint shell and markdown
	@command -v shellcheck >/dev/null && shellcheck -S warning bin/dss-lab bin/lib/*.sh tests/run_tests.sh || echo "shellcheck not installed"
	@command -v markdownlint >/dev/null && markdownlint . || echo "markdownlint not installed"

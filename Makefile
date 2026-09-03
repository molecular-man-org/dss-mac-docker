SHELL := /bin/bash
SKILLS_DIR := $(HOME)/.claude/skills
REPO := $(shell pwd)

.PHONY: help install uninstall test lint

help: ## Show available targets
	@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST) | \
		awk -F':.*##' '{printf "  %-12s %s\n", $$1, $$2}'

install: ## Symlink skills into ~/.claude/skills
	@mkdir -p "$(SKILLS_DIR)"
	@for s in $(REPO)/skills/*/; do \
		[ -e "$$s/SKILL.md" ] || continue; \
		n=$$(basename "$$s"); \
		ln -sfn "$$s" "$(SKILLS_DIR)/$$n" && echo "linked $$n"; \
	done

uninstall: ## Remove the skill symlinks
	@for s in $(REPO)/skills/*/; do \
		n=$$(basename "$$s"); \
		[ -L "$(SKILLS_DIR)/$$n" ] && rm "$(SKILLS_DIR)/$$n" && echo "unlinked $$n"; \
	done; true

test: ## Run unit tests
	@bash tests/run_tests.sh

lint: ## Lint shell and markdown
	@command -v shellcheck >/dev/null && shellcheck bin/dss-lab bin/lib/*.sh || echo "shellcheck not installed"
	@command -v markdownlint >/dev/null && markdownlint . || echo "markdownlint not installed"

.DEFAULT_GOAL := help
SHELL := /bin/bash

PWD := $(shell realpath $(dir $(lastword $(MAKEFILE_LIST))))
DEPS_DIR := $(PWD)/.deps

.PHONY: init deps tester linter lint test test-nvim vendor vendor-check help clean
.PHONY: lint-vint vint-int check-vint

THEMIS_URL    := https://github.com/thinca/vim-themis.git
THEMIS_DIR    := $(DEPS_DIR)/vim-themis
THEMIS_COMMIT := 355c34b1bff03a8fd3744e3ad2dd0627c0692716

VIMLPARSER_URL    := https://github.com/ynkdir/vim-vimlparser.git
VIMLPARSER_DIR    := $(DEPS_DIR)/vim-vimlparser
VIMLPARSER_COMMIT := 4495d3957dbf84d8c8f9a58abe021d1554aec631

VIMLINT_URL    := https://github.com/syngan/vim-vimlint.git
VIMLINT_DIR    := $(DEPS_DIR)/vim-vimlint
VIMLINT_COMMIT := cec40c28f119a5f4b92ceb0b6aae525122a81244

LINT_DIRS ?= autoload test vendor

define CLONE_AND_OPTIONAL_PIN
	@set -euo pipefail; \
	url="$(1)"; dir="$(2)"; commit="$(3)"; \
	mkdir -p "$(DEPS_DIR)"; \
	if [ ! -d "$$dir/.git" ]; then \
		git clone "$$url" "$$dir"; \
	fi; \
	if [[ "$$commit" =~ ^[0-9a-fA-F]{7,40}$$ ]]; then \
		git -C "$$dir" checkout -q --detach "$$commit"; \
	fi; \
	echo "OK: $$dir @ $$(git -C "$$dir" rev-parse --short HEAD)"
endef

init: linter tester ## init

deps: tester linter ## clone deps (optionally pin)

tester: $(THEMIS_DIR) ## clone tester

linter: $(VIMLPARSER_DIR) $(VIMLINT_DIR) ## clone linter

$(THEMIS_DIR):
	$(call CLONE_AND_OPTIONAL_PIN,$(THEMIS_URL),$(THEMIS_DIR),$(THEMIS_COMMIT))

$(VIMLPARSER_DIR):
	$(call CLONE_AND_OPTIONAL_PIN,$(VIMLPARSER_URL),$(VIMLPARSER_DIR),$(VIMLPARSER_COMMIT))

$(VIMLINT_DIR):
	$(call CLONE_AND_OPTIONAL_PIN,$(VIMLINT_URL),$(VIMLINT_DIR),$(VIMLINT_COMMIT))

test: tester ## testing with vim-themis (Vim)
	$(THEMIS_DIR)/bin/themis --reporter spec -r test

test-nvim: tester ## testing with vim-themis (Neovim)
	THEMIS_VIM=nvim \
	THEMIS_ARGS='--headless -u NONE -i NONE -n' \
	$(THEMIS_DIR)/bin/themis --reporter spec -r test

# vimlint.sh's -c/-e handlers rely on GNU sed's \+ (unsupported by BSD sed),
# so on macOS the generated config is invalid VimL: every run exits 1 before
# reporting anything and func_abort=1 is silently dropped.  Invoke vimlint
# directly with the same config instead.
# EVL108 is suppressed: it predates version features like has('nvim-0.9').
LINT_CONFIG := {'quiet': 1, 'func_abort': 1, 'EVL102': {'l:_': 1}, 'EVL103': {':': 1}, 'EVL108': {':': 1}}

lint: linter ## linting with vimlint
	@ret=0; \
	for d in $(LINT_DIRS); do \
		tf=$$(mktemp); \
		vim -u NONE -i NONE -es -N \
			-c "set rtp+=$(VIMLINT_DIR)" -c "set rtp+=$(VIMLPARSER_DIR)" \
			-c "let g:vimlint#config = $(LINT_CONFIG)" \
			-c "call vimlint#vimlint('$$d', {'output': '$$tf'})" -c 'qall!' \
			< /dev/null || { echo "vim exited non-zero linting $$d"; ret=1; }; \
		grep -a -w -E 'Error|Warning' "$$tf" | grep -v EVP_0 && ret=2; \
		grep -a EVP_0 "$$tf" | sed 's/^/NOTE upstream vimlint internal error (not a finding): /'; \
		rm -f "$$tf"; \
	done; \
	exit $$ret

# Hosts that vendor winref under their own autoload namespace.
# See "Namespace" in README.md: two plugins shipping the same
# autoload/winref.vim would shadow each other on 'runtimepath'.
VENDOR_SRC   ?= autoload/winref.vim
VENDOR_GUARD ?= vendor/vendor.vim
VENDOR_HOSTS ?= ghreview:$(PWD)/../vim-ghreview winreach:$(PWD)/../vim-winreach \
                vim_folds:$(PWD)/../vim-folds

SHA256 := $(shell command -v sha256sum >/dev/null 2>&1 && echo sha256sum || echo 'shasum -a 256')

# $(1): "write" | "check"
define VENDOR_RUN
	@set -uo pipefail; \
	mode="$(1)"; src="$(VENDOR_SRC)"; guard="$(VENDOR_GUARD)"; rc=0; \
	if [ ! -f "$$src" ]; then echo "ERROR: canonical $$src not found" >&2; exit 2; fi; \
	src_sha=$$($(SHA256) "$$src" | cut -d' ' -f1); \
	for entry in $(VENDOR_HOSTS); do \
		ns="$${entry%%:*}"; root="$${entry#*:}"; \
		case "$$ns" in *[!A-Za-z0-9_]*) \
			echo "ERROR: namespace '$$ns' is not [A-Za-z0-9_]+" >&2; exit 2;; esac; \
		if [ ! -d "$$root" ]; then echo "SKIP: $$root not found"; continue; fi; \
		out="$$root/autoload/$$ns/winref.vim"; \
		body=$$(mktemp); new=$$(mktemp); \
		sed -e "s/winref#/$$ns#winref#/g" -e '1d' "$$src" > "$$body"; \
		body_sha=$$($(SHA256) "$$body" | cut -d' ' -f1); \
		{ \
			echo "\" $$ns#winref - VENDORED from kis9a/vim-winref; do not edit here."; \
			echo "\" Regenerate with 'make vendor' in the vim-winref checkout."; \
			echo "\" winref-vendor: src=$$src_sha body=$$body_sha"; \
			cat "$$body"; \
		} > "$$new"; \
		rm -f "$$body"; \
		if [ "$$mode" = write ]; then \
			mkdir -p "$$(dirname "$$out")"; mv "$$new" "$$out"; echo "OK: $$out"; \
			if [ -f "$$guard" ]; then \
				mkdir -p "$$root/test"; cp "$$guard" "$$root/test/vendor.vim"; \
				echo "OK: $$root/test/vendor.vim"; \
			fi; \
		else \
			if [ ! -f "$$out" ]; then \
				echo "MISSING: $$out"; rc=1; \
			elif ! cmp -s "$$out" "$$new"; then \
				echo "DRIFT: $$out differs from what 'make vendor' produces:"; \
				diff -u "$$out" "$$new" | sed 's/^/    /'; rc=1; \
			else \
				echo "FRESH: $$out"; \
			fi; \
			rm -f "$$new"; \
		fi; \
	done; \
	exit $$rc
endef

vendor: ## copy autoload/winref.vim into each host under its own namespace
	$(call VENDOR_RUN,write)

vendor-check: ## fail if any host's vendored copy is stale or hand-edited
	$(call VENDOR_RUN,check)

lint-vint: check-vint ## linting with vint
	vint autoload test

vint-int: ## install vint using pip
	pip install vint

check-vint: ## check vint command exists
	command -v vint >/dev/null 2>&1

clean: ## remove cloned deps
	rm -rf $(DEPS_DIR)

help: ## help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

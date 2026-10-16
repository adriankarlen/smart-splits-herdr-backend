# Smart-splits core revision to test and typecheck against
SMART_SPLITS_REV := "v3.0.0"

# Clone smart-splits core at the pinned revision (no-op if already there)
[private]
deps:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="deps/smart-splits.nvim"
    if [ -d "$dir" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$(git -C "$dir" rev-parse '{{ SMART_SPLITS_REV }}^{commit}' 2>/dev/null)" ]; then
      exit 0
    fi
    rm -rf "$dir"
    mkdir -p deps
    git clone --filter=blob:none --no-checkout https://github.com/smart-splits-nvim/smart-splits.nvim "$dir"
    git -C "$dir" checkout --quiet '{{ SMART_SPLITS_REV }}'

# Force re-clone smart-splits core
[private]
deps-force:
    rm -rf deps/smart-splits.nvim
    just deps

# Run all tests
test: test-core test-integration

# Run the hermetic tests, against a fake herdr
test-core: deps
    SMART_SPLITS_DIR="$(pwd)/deps/smart-splits.nvim" busted --run=core

# Run the tests that drive a real herdr server in a private session
test-integration: deps
    SMART_SPLITS_DIR="$(pwd)/deps/smart-splits.nvim" busted --run=integration

# Check formatting
fmt-check:
    stylua --check lua tests
    shfmt --indent 2 --case-indent --diff scripts/herdr-navigate.sh
    yamlfmt -gitignore_excludes -dry .
    prettier --check "**/*.{json,jsonc}"
    tombi format --offline --check .
    nixfmt --check flake.nix treefmt.nix

# Format code
fmt:
    stylua lua tests
    shfmt --indent 2 --case-indent --write scripts/herdr-navigate.sh
    yamlfmt -gitignore_excludes .
    prettier --write "**/*.{json,jsonc}"
    tombi format --offline .
    nixfmt flake.nix treefmt.nix

# Run linters
lint:
    selene ./lua/ ./tests/
    shellcheck scripts/herdr-navigate.sh
    actionlint
    statix check

# Run EmmyLua type checking
typecheck: deps
    VIMRUNTIME="$(nvim --clean -i NONE --headless --cmd 'lua io.write(vim.env.VIMRUNTIME)' --cmd 'quitall')" \
    emmylua_check --warnings-as-errors .

# Run all checks
check: fmt-check lint typecheck test

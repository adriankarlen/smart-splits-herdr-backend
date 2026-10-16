# Contributing

Thank you for your interest in contributing to `smart-splits-backend-herdr`!

## Development Setup

### Prerequisites (Preferred: Nix + direnv)

If you have Nix and direnv installed:

```sh
direnv allow
```

All dependencies are provided by the Nix flake. The first time, run `nix flake lock` to pin the inputs.

### Prerequisites (Alternative: Manual Installation)

If you prefer to install tools manually:

```sh
# macOS
brew install neovim herdr jq stylua emmylua_check selene shellcheck shfmt luajit luarocks just \
  yamlfmt prettier tombi nixfmt actionlint statix

LUAJIT_PREFIX="$(brew --prefix luajit)"
ROCKS=(--lua-version=5.1 --lua-dir="$LUAJIT_PREFIX" --local)
luarocks "${ROCKS[@]}" install busted 2.3.0
luarocks "${ROCKS[@]}" install nlua 0.3.2
eval "$(luarocks "${ROCKS[@]}" path --bin)"
```

### Running Tests

Run all checks before submitting a PR:

```sh
just check
```

This runs:

- Formatting checks (Stylua, shfmt, yamlfmt, prettier, tombi, nixfmt)
- Linting (Selene, shellcheck, actionlint, statix)
- EmmyLua type checking (`emmylua_check`, configured by `.emmyrc.json`)
- Busted test suites

Individual commands:

```sh
just test             # Run both test suites
just test-core        # Hermetic tests, against a fake herdr
just test-integration # Tests that drive a real herdr server
just lint             # Run linters
just fmt-check        # Check formatting
just fmt              # Auto-format code
just typecheck        # Type checking
```

Test and typecheck recipes clone smart-splits core into `deps/` at the revision pinned in the `justfile`. It is a
development dependency only: the tests use its `protocol_tests` module and the type checker reads its annotations.

To run the tests against Neovim nightly:

```sh
nix develop .#ci-nightly --command just test
```

## Implementation Guidelines

### Layout

```
lua/smart-splits-backend-herdr/
├── init.lua       # the backend table core sees
├── config.lua     # defaults and setup(), inert by protocol
├── transport.lua  # socket first, `herdr` CLI fallback; the only module doing I/O
├── herdr.lua      # typed wrappers, one per herdr request
├── layout.lua     # pure geometry over herdr's layout snapshot
├── move.lua       # move(), including at_edge and zoom
├── resize.lua     # resize(), converting cells to herdr's split fractions
└── health.lua     # :checkhealth body, under a header core emits
herdr-plugin.toml          # the herdr half: plugin manifest
scripts/herdr-navigate.sh  # the herdr half: what the key bindings run
tests/
├── fake_herdr.lua  # a fake herdr server, plugged in below the transport
├── helpers.lua
├── core/           # hermetic, against the fake herdr
└── integration/    # against a real herdr server in a private session
```

### Backend Protocol

This backend implements the [v3 protocol](https://github.com/smart-splits-nvim/smart-splits.nvim/blob/master/PROTOCOL.md).
Two rules from it are easy to break by accident:

- **`detect()` must be cheap and free of side effects.** No subprocesses and no socket requests: core
  resolves backends inside its own `setup()`.
- **`setup()` must stay inert.** Users install several backends and list them in priority order, so
  every installed backend is configured on every startup.

### What herdr does

A few herdr behaviours the code relies on. The integration suite checks each of them:

- `pane.focus_direction` never wraps. At an edge it answers `changed = false, reason = "no_neighbor"`.
- `pane.split` only splits `right` or `down`. Left and up are a split followed by `pane.swap`.
- `pane.resize` takes `amount` as a change to the split's ratio (`0.1` is 10% of the split), not as
  cells. It moves the pane's border on the `direction` side, or the opposite border when there is
  none.
- The CLI cannot focus a pane by id, so with the CLI transport, wrapping walks pane by pane.

### Type Annotations

Use LuaCATS annotations on every function, and keep `just typecheck` clean. It runs with warnings as
errors.

### Testing

All new functionality should include tests.

`tests/core/*_spec.lua` runs against `tests/fake_herdr.lua`, which keeps a layout of pane rectangles,
answers requests from that geometry, and records every request. These tests never touch a real herdr,
and behave the same whether or not you run them from inside one. `transport_spec.lua` uses a real Unix
socket served from inside the test process, and a fake `herdr` executable.

`tests/integration/*_spec.lua` starts a real `herdr server` in a named session with `HOME` and
`XDG_CONFIG_HOME` pointed at a temporary directory under `/tmp`, so your own herdr is never touched.
The directory is short on purpose, because Unix socket paths have a length limit of about 104 bytes.
These tests are marked pending when `herdr` is not on the `$PATH`.

## Code Style

- 2-space indentation
- Single quotes for strings
- Maximum line length: 120 characters
- Sorted requires

These are enforced by Stylua, shfmt, yamlfmt, prettier, tombi, and nixfmt.

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `just check` to ensure all checks pass
5. Submit a pull request

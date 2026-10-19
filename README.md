# smart-splits-backend-herdr

A [herdr](https://herdr.dev) backend for [smart-splits.nvim](https://github.com/smart-splits-nvim/smart-splits.nvim)
v3.

One set of keys works across the Neovim/herdr boundary. `<C-hjkl>` moves through Neovim's windows until there are no
more, then carries on through herdr's panes. At the outer edge of herdr, the movement keys can wrap around or create a
new herdr pane, depending on what you set. From inside Neovim, `<M-hjkl>` also resizes the herdr pane once Neovim's
window fills that direction.

smart-splits.nvim included herdr support up to v2. v3 moved every multiplexer out into a separate plugin, and this
plugin brings herdr support back, against the
[v3 protocol](https://github.com/smart-splits-nvim/smart-splits.nvim/blob/master/PROTOCOL.md).

## Requirements

- Neovim 0.11 or newer
- smart-splits.nvim v3
- herdr 0.7.0 or newer (tested with 0.9)
- For the herdr half: `bash`, and `jq` so that herdr can tell a Neovim pane from any other pane. Linux and macOS only.

## Installation

The integration has two halves:

- **Neovim side**: this Lua backend. When you are in Neovim's edge window, it moves you into the neighbouring herdr pane.
- **herdr side**: a herdr plugin, which lives in this same repository. When the key is pressed in a pane running
  Neovim, the plugin sends it on to Neovim. In any other pane, the plugin moves herdr focus.

With only the Neovim side, you can leave Neovim but you cannot get back in with the same keys.

### Neovim

With `vim.pack`:

```lua
vim.pack.add({
  'https://github.com/smart-splits-nvim/smart-splits.nvim',
  'https://github.com/adriankarlen/smart-splits-backend-herdr',
})

require('smart-splits').setup({
  mux = { backend = 'smart-splits-backend-herdr' },
})
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'smart-splits-nvim/smart-splits.nvim',
  version = '^3.0.0',
  dependencies = {
    {
      'adriankarlen/smart-splits-backend-herdr',
      main = 'smart-splits-backend-herdr',
      opts = {}, -- see Options
    },
  },
  opts = {
    mux = { backend = 'smart-splits-backend-herdr' },
  },
}
```

Then map the keys as smart-splits.nvim describes:

```lua
vim.keymap.set('n', '<C-h>', require('smart-splits').move_cursor_left)
vim.keymap.set('n', '<C-j>', require('smart-splits').move_cursor_down)
vim.keymap.set('n', '<C-k>', require('smart-splits').move_cursor_up)
vim.keymap.set('n', '<C-l>', require('smart-splits').move_cursor_right)
vim.keymap.set('n', '<A-h>', require('smart-splits').resize_left)
vim.keymap.set('n', '<A-j>', require('smart-splits').resize_down)
vim.keymap.set('n', '<A-k>', require('smart-splits').resize_up)
vim.keymap.set('n', '<A-l>', require('smart-splits').resize_right)
```

Lazy loading is fine. Unlike the tmux backend, Neovim does not have to mark its pane: the herdr side checks the pane's
foreground process.

If you also use other multiplexers, list the backends in priority order and put herdr first, because it is the inner
multiplexer:

```lua
mux = { backend = { 'smart-splits-backend-herdr', 'smart-splits-backend-ghostty' } },
```

### herdr

Install the herdr plugin from GitHub:

```sh
herdr plugin install adriankarlen/smart-splits-backend-herdr
```

Or link the copy your Neovim plugin manager already has. The path depends on your plugin manager:

```sh
# vim.pack
herdr plugin link ~/.local/share/nvim/site/pack/core/opt/smart-splits-backend-herdr
# lazy.nvim
herdr plugin link ~/.local/share/nvim/lazy/smart-splits-backend-herdr
```

Bind the keys in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "ctrl+h"
type = "plugin_action"
command = "smart-splits-backend-herdr.left"
description = "navigate left (neovim/herdr)"

[[keys.command]]
key = "ctrl+j"
type = "plugin_action"
command = "smart-splits-backend-herdr.down"
description = "navigate down (neovim/herdr)"

[[keys.command]]
key = "ctrl+k"
type = "plugin_action"
command = "smart-splits-backend-herdr.up"
description = "navigate up (neovim/herdr)"

[[keys.command]]
key = "ctrl+l"
type = "plugin_action"
command = "smart-splits-backend-herdr.right"
description = "navigate right (neovim/herdr)"
```

Then reload herdr:

```sh
herdr server reload-config
```

On each keypress, the plugin does one of three things:

1. If the focused pane is running Vim or Neovim, it sends the key into the pane. smart-splits.nvim takes over from
   there.
2. If not, it moves herdr focus in that direction.
3. If there is no pane in that direction, it sends the key back to the pane. Shell bindings such as `<C-l>` (clear) and
   `<C-h>` (backspace) keep working.

Some other programs handle `<C-hjkl>` themselves. To add them to step 1, set `SMART_SPLITS_HERDR_PASSTHROUGH_RE` in
herdr's environment. The value is a regex, matched against the lower-cased foreground process name:

```sh
export SMART_SPLITS_HERDR_PASSTHROUGH_RE='^(lazygit|k9s)$'
```

### Coming from smart-splits.nvim v2

v2 had its own herdr plugin, called `smart-splits.nvim`. v3 removed that plugin's manifest, so herdr now lists it with
the warning `manifest unavailable`. To move to this plugin:

```sh
herdr plugin unlink smart-splits.nvim
herdr plugin install adriankarlen/smart-splits-backend-herdr   # or `herdr plugin link`, see above
```

In `config.toml`, change each `command = "smart-splits.nvim.<dir>"` to `command = "smart-splits-backend-herdr.<dir>"`.
Then reload herdr. `:checkhealth smart-splits` warns you if the old plugin is still registered.

## Options

Every option has a default, so calling `setup()` is optional. Calling it only stores the values.

```lua
require('smart-splits-backend-herdr').setup({
  -- set to false to stop this backend from ever being selected
  enable = true,
  -- refuse to move out of a zoomed herdr pane
  disable_nav_when_zoomed = true,
  -- cells to resize by when smart-splits passes no amount
  resize_amount = 3,
  -- milliseconds to wait for herdr before giving up and falling back to plain Neovim behaviour
  timeout = 300,
  -- 'auto': the socket in $HERDR_SOCKET_PATH, falling back to the `herdr` CLI
  -- 'socket': the socket only
  -- 'cli': the `herdr` CLI only
  transport = 'auto',
})
```

## Behaviour

### Moving

When you are in Neovim's edge window and move further, the backend asks herdr to focus the neighbouring pane. herdr
never wraps by itself, so when there is no pane that way, smart-splits.nvim's `move.at_edge` setting decides what
happens:

| `move.at_edge` | At the outer edge of herdr                                                                    |
| -------------- | --------------------------------------------------------------------------------------------- |
| `'stop'`       | Nothing happens.                                                                              |
| `'wrap'`       | Focus moves to the herdr pane on the opposite edge, in the same row or column.                |
| `'split'`      | A new herdr pane opens on that side and gets focus.                                           |
| a function     | smart-splits.nvim calls your function.                                                        |

`'wrap'` falls back to wrapping among Neovim's own windows when herdr has no pane to wrap to. For example, the Neovim
pane may already fill that row or column on its own.

### Resizing

smart-splits.nvim calls the backend only when the Neovim window already fills that axis. The backend then moves a
border of its herdr pane towards the direction you pressed. This only works from inside Neovim: the herdr plugin does
not handle resize keys. In other panes, use herdr's own `resize_mode` or `resize_pane_*` bindings. herdr measures resizes as a fraction of the split, so the
backend reads the layout and converts smart-splits.nvim's cell count into that fraction.

### Zoom

When `disable_nav_when_zoomed` is set, moving out of a zoomed herdr pane does nothing, and smart-splits.nvim applies
`move.at_edge` inside Neovim.

### Speed

Requests go straight to herdr's socket from inside Neovim, without starting a process. One request takes about 1 ms. A
move needs one or two requests: two with `disable_nav_when_zoomed`, because the backend first checks for zoom. If the
socket cannot be reached, the backend uses the `herdr` CLI instead, which takes about 15 ms per request. The CLI
cannot focus a pane by id, so with the CLI, `'wrap'` steps across the panes one at a time.

The herdr-side script runs only when you press a key in herdr. It takes about 45 ms.

## Health

```vim
:checkhealth smart-splits
```

This checks the `herdr` binary, the socket, whether the server answers, and whether the herdr plugin is installed and
enabled. It also warns about the v2 plugin. To check this backend without going through core, run
`:checkhealth smart-splits-backend-herdr`.

## Caveats

- `<C-h>` and Backspace send the same byte unless the terminal uses the kitty keyboard protocol. Neovim 0.10 and newer
  turns that protocol on in herdr panes, so `<C-h>` stays separate from Backspace there. Older Vim may need `<BS>`
  mapped as well.
- Across herdr panes, the navigation keys take priority over the shell's own bindings, as they do in tmux. In a shell
  with no pane in that direction, the keys still reach the shell.

## License

MIT. Parts of the herdr-side script come from smart-splits.nvim v2's herdr integration.

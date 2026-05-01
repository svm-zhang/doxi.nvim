# doxi.nvim

`doxi.nvim` is a lightweight Neovim plugin for authoring Python docstring examples as real doctest-style transcripts.

It is built for one narrow workflow: select a docstring example region, open a focused floating session, write or edit plain Python code, run it in a real interpreter, and apply the generated transcript back into the original docstring without leaving Neovim.

## Feature Highlights

- Author new examples from a blank docstring line.
- Edit an existing contiguous doctest block by importing it back into plain Python code.
- Reuse shared imports from the top of one supported `Examples` section.
- Run all code or a visual selection from the session editor.
- Render deterministic doctest transcripts with `>>>` and `...` prompts.
- Keep a persistent Python subprocess alive for the session lifetime.
- Restart the interpreter cleanly or restart and rerun everything.
- Reuse supported source-buffer Python LSP clients inside the editor pane.
- Prefer the source-buffer interpreter when it can be recovered, and fall back safely when it cannot.
- Apply the transcript back to the original selected source range safely.

## Requirements

- Neovim `0.11.0+`.
- Python available on your machine.
- Python Treesitter parser available to Neovim.

The most common way to satisfy the parser requirement is with
`nvim-treesitter`, but `doxi.nvim` uses Neovim's built-in Treesitter API at
runtime.

If the Python parser is missing, `doxi.nvim` does not enable normally. It fails
early during setup with a clear message instead of waiting until the first
`:DoxiOpen`.

## Installation

### `lazy.nvim`

For normal installation:

```lua
return {
  {
    "svm-zhang/doxi.nvim",
    ft = { "python" },
    keys = {
      {
        "<leader>de",
        function()
          require("doxi").open_visual()
        end,
        mode = "x",
        desc = "Open doxi for selection",
      },
    },
    config = function()
      require("doxi").setup()
    end,
  },
}
```

After installation, make sure the Python Treesitter parser is actually
available, then run:

```vim
:checkhealth doxi
```

## Configuration

Default configuration:

```lua
require("doxi").setup({
  python_path = nil,
  lsp = {
    enabled = true,
    warn_unsupported = true,
    signature_help = {
      provider = "ambient",
    },
  },
  ui = {
    width = 100,
    height = 0.75,
    imports_height = 2,
    editor_height = 0.45,
    hints_height = 2,
    border = "rounded",
    lock_focus = true,
    tmux_navigation = true,
  },
  session_keymaps = {
    run_all = "<leader>ra",
    run_selection = "<leader>rs",
    restart = "<leader>rr",
    restart_rerun = "<leader>rR",
    apply = "<leader>da",
    cancel = "q",
    focus_next_pane = "<leader>j",
    focus_previous_pane = "<leader>k",
    tmux_left = "<C-h>",
    tmux_down = "<C-j>",
    tmux_up = "<C-k>",
    tmux_right = "<C-l>",
  },
})
```

Configuration notes:

| Option | Default / choices | Meaning |
| --- | --- | --- |
| `python_path` | `nil` or explicit Python path | Takes priority over automatic interpreter discovery. |
| `lsp.enabled` | `true` | Enables editor-pane reuse of supported source-buffer Python LSP clients: `pyright`, `basedpyright`, `pylsp`, and `ruff`. |
| `lsp.warn_unsupported` | `true` | Warns when attached source-buffer clients are unsupported or when interpreter fallback breaks alignment. |
| `lsp.signature_help.provider` | `"ambient"` or `"doxi"` | `"ambient"` keeps your editor's existing signature-help behavior. `"doxi"` makes `doxi` request and render signature help inside the `doxi` editor pane. |
| `lsp.signature_help.*` | floating-window options such as `width`, `height`, `focusable`, `mouse` | Matter only when `lsp.signature_help.provider = "doxi"`. The `doxi` path is scoped to the editor pane and may suppress known conflicting signature-help providers there when needed, but it does not promise universal suppression of arbitrary third-party plugins. |
| `ui.width` | fixed columns like `100` or ratio like `0.75` | Controls session width. |
| `ui.imports_height` | integer | Sets the minimum height of the read-only shared-imports pane. |
| `session_keymaps` | mapping table | Only affect the floating session buffers, not your source buffer. |

Suggested source-buffer keybind:

```lua
vim.keymap.set("x", "<leader>de", function()
  require("doxi").open_visual()
end, { desc = "Open doxi" })
```

Recommended readiness check:

```vim
:checkhealth doxi
```

## How It Works

Every `doxi` session opens four floating panes:

- Top pane: read-only shared imports
- Upper-middle pane: editable Python code
- Lower-middle pane: read-only doctest transcript
- Bottom pane: read-only key hints

The editor pane uses plain Python source. You do not type `>>>` or `...` there. The shared-imports pane is read-only and shows the imports that `doxi` will replay before runs. The transcript pane is generated from execution results and is the only thing applied back into the docstring.

## Docstring Detection

`doxi.nvim` uses Treesitter-backed canonical docstring detection in `v0.1.1+`.

Accepted docstring targets:

- Module docstrings.
- Class docstrings.
- Function and method docstrings.
- Async function docstrings.

The selection must stay wholly inside one canonical docstring node.

Rejected string targets include:

- Assigned triple-quoted strings.
- Triple-quoted strings passed as function arguments.
- Later standalone strings inside a function body.
- Selections that cross outside the docstring.

This means `doxi` is checking for real Python docstrings, not just any
triple-quoted string that happens to contain doctest-like text.

## Use case 1: Edit an existing doctest block

This is the most direct workflow and the easiest way to use the plugin.

1. In a Python docstring, visually select a contiguous doctest block.
2. Run `:'<,'>DoxiOpen` or trigger your visual-mode mapping.
3. `doxi` strips the prompts and output, discovers shared imports above the selected block when applicable, and opens the session.
4. Change the code.
5. Run it again inside the session.
6. Apply the transcript back to the original selection.

For instance, select a doctest block from a docstring:

```python
>>> def f(x):
...     return x + 1
>>> f(3)
4
>>> 1 / 0
Traceback (most recent call last):
...
ZeroDivisionError: division by zero
```

`doxi.nvim` imports/injects the following into editor pane when session opens:

```python
def f(x):
    return x + 1
f(3)
1 / 0
```

If the selected block is below a top-of-section import prologue, those imports
appear in the read-only imports pane and are replayed before runs. They do not
appear in the visible transcript unless shared import replay fails.

## Use case 2: Create a new example from scratch

1. In a Python docstring, visually select an empty line where the example should go.
2. Run `:'<,'>DoxiOpen` or your visual-mode mapping.
3. Write plain Python code in the editor pane.
4. Run the code.
5. Apply the generated transcript back to the original blank selection.

`doxi` preserves the surrounding docstring indentation and blank-line separators. If you open from a blank line below an existing doctest region, it also synthesizes the leading separator needed to keep the examples visually separated.

If you open above the previous top block in the section, shared imports below
that insertion point are not inherited.

## Editor-Pane LSP Support

When `lsp.enabled = true`, `doxi.nvim` can reuse supported Python LSP clients
already attached to the source buffer and attach them to the session editor
pane. This lets the editor pane behave more like a normal Python buffer, with
features such as completion, diagnostics, hover, and signature help when the
underlying LSP server provides them.

Supported clients currently include `pyright`, `basedpyright`, `pylsp`. The exact behavior depends on the server.

Signature help has two rendering modes:

- `lsp.signature_help.provider = "ambient"` keeps your normal Neovim signature
  help setup.
- `lsp.signature_help.provider = "doxi"` makes `doxi.nvim` request signature
  help and render it in its own floating window inside the session editor pane.

The `doxi` signature provider is only a rendering choice for the session editor
pane. Under the hood, it uses Neovim's built-in LSP
`textDocument/signatureHelp` request, converts the response with
`vim.lsp.util.convert_signature_help_to_markdown_lines()`, and renders it with
`vim.lsp.util.open_floating_preview()`. It does not turn `doxi.nvim` into a
general LSP manager.

## Shared Import Rules

`doxi.nvim` supports shared imports inside one supported `Examples` section.

Supported header forms:

- Google-style:
  - `Examples:`
- NumPy-style:
  - `Examples`
  - `--------`

Discovery rules:

- `doxi` scans from the supported `Examples` header down to the selected block.
- Blank lines and prose titles are ignored.
- Only doctest statements are considered for shared-import discovery.
- Shared imports are the leading consecutive import statements in that doctest stream.
- Discovery stops at the first non-import doctest statement.
- Discovery never scans past the selected block boundary.

Practical consequences:

- The first doctest block in a section has no inherited shared imports.
- Later blocks can inherit top-of-section imports.
- Prose between blocks does not break shared-import discovery.
- Later block-local imports are not promoted into shared imports.
- Successful shared-import replay stays out of the visible transcript.
- If shared-import replay fails, editor code does not run and the failure is
  shown in the transcript pane.

## Interpreter Discovery

Before the session opens, `doxi` confirms which Python interpreter it will use.

When a supported Python LSP is attached to the source buffer and `doxi` can
recover its interpreter context, the picker shows only that aligned
interpreter.

Otherwise, `doxi` falls back to normal interpreter discovery. Discovery
currently checks, in priority order:

1. Configured `python_path`.
2. Active `VIRTUAL_ENV`.
3. Project-local `.venv/bin/python`.
4. Project-local `venv/bin/python`.
5. Poetry environment executable, when available.
6. `python3`.
7. `python`.
8. Manual path entry.

When fallback discovery finds multiple candidates, `doxi` suppresses repeated
entries for the same environment while still showing genuinely different
interpreters from different sources.

If `doxi` must fall back while a supported source-buffer LSP is attached, it
warns that editor assistance and code execution may not match.

Canceling the picker leaves the source buffer unchanged and does not open a
session.

## Commands

### Source buffer entry

| Command | Use |
| --- | --- |
| `:DoxiOpen` | Open a session from a visual selection inside a Python docstring. The selection must be either blank lines or a contiguous doctest block. |

### Session Commands

| Command | Use |
| --- | --- |
| `:DoxiRunAll` | Run the entire code in editor pane against the current live interpreter state. |
| `:DoxiRunSelection` | Run the selected code from the editor pane only. |
| `:DoxiRestart` | Start a fresh interpreter and clear the transcript. |
| `:DoxiRestartRerun` | Start a fresh interpreter, then rerun the full editor buffer. |
| `:DoxiApply` | Replace the originally selected source range with the current transcript. |
| `:DoxiCancel` | Close the session without modifying the source buffer. |

## Default Session Keymaps

These mappings apply inside the floating session buffers:

| Action | Default |
| --- | --- |
| run all | `<leader>ra` |
| run selection | `<leader>rs` |
| restart | `<leader>rr` |
| restart and rerun | `<leader>rR` |
| apply transcript | `<leader>da` |
| cancel session | `q` |

## Selection Boundaries and Error Cases

`doxi` is intentionally strict about what `:DoxiOpen` accepts.

Valid selections:

- One or more blank lines inside one canonical Python docstring.
- A contiguous doctest region inside one canonical Python docstring.
- Multiple doctest prompt/output groups separated only by blank lines.
- A selection inside one supported `Examples` section.

Invalid selections:

- Anything outside a canonical Python docstring.
- Non-Python buffers.
- Triple-quoted strings that are not real docstrings.
- Mixed prose and doctest content inside the selected region.
- A region that starts with prose instead of a doctest prompt.
- Broken doctest structure, such as a continuation line without an active statement.
- A docstring with more than one supported `Examples` section.

Typical user-facing failures:

- `Visual-select an empty docstring line or contiguous doctest block first.`
- `Select an empty docstring line or doctest block inside a Python docstring.`
- `doxi.nvim requires the Python Treesitter parser for docstring detection.`
- `Selection does not start with a doctest prompt.`
- `Invalid doctest block: unexpected prose or title at line N.`
- `doxi.nvim supports only one Examples section per docstring.`
- `doxi.nvim found mixed Google-style and NumPy-style Examples sections in one docstring. Use one Examples section style per docstring.`

Session-specific boundaries:

- `:DoxiRunSelection` only works when the editor pane is focused and a visual selection exists there.
- The transcript pane is read-only.
- `:DoxiApply` always writes back to the original captured range.
- If the original source range changed incompatibly before apply, `doxi` aborts instead of guessing.

## Behavior Boundaries

These are deliberate operating rules:

- The shared-imports pane is read-only and exists only to show replayed import context.
- `:DoxiRunSelection` only works when the editor pane is focused and has a visual selection.
- The transcript pane is read-only and cannot be edited directly.
- Transcript rendering is plain doctest text, not terminal emulation or rich output.
- `:DoxiApply` always writes back to the originally captured source range.
- If the source range changed incompatibly before apply, `doxi` aborts instead of guessing.

## Current Limitations

These are real `v0.1.x` constraints:

- Only Python is supported.
- `v0.1.1+` requires the Python Treesitter parser before `doxi.nvim` will enable normally.
- Docstring detection is limited to canonical Python docstrings.
- Shared import context is limited to one supported `Examples` section per docstring.
- Doctest import supports contiguous doctest regions only.
- Mixed prose plus doctest parsing is intentionally unsupported.
- The transcript pane shows the latest run result only; it does not keep run history.

## Non-Goals

`doxi.nvim` is a focused docstring example authoring tool. It is not trying to be:

- A notebook environment.
- A terminal emulator.
- An AI example generator.

## Testing

Run the headless test suite from the project root:

```sh
nvim --headless -u NONE -c "lua dofile('scripts/run_tests.lua')"
```

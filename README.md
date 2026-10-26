# winref

Cross-tab window identity for Vim / Neovim.

`win_id2win()`, `bufwinid()`, `getwinvar()` and `setwinvar()` all resolve only
windows of the **current tab page**. Once the user switches tabs, existence
checks silently return "not found" and option writes silently do nothing — no
error, no warning. `getwininfo()` and `win_execute()` span tab pages; every query
and every cross-window access here is built on those two. `winrestcmd()` is
used by `without_equalize()` alone, and Neovim additionally needs
`nvim_win_get_config()` to recognise floating windows.

```vim
" tab 1 holds the window; we are in tab 2
echo win_id2win(winid)                       " 0      -- looks gone
echo bufwinid(bufnr)                         " -1     -- looks gone
call setwinvar(winid, '&foldmethod', 'indent')  "     -- does nothing

echo winref#get(winid).tabnr                 " 1      -- found
call winref#execute(winid, 'setlocal foldmethod=indent')  " applied
```

None of this is to say Vim cannot reach another tab page: `win_id2tabwin()`
turns a window ID into a tab and window number, and `gettabwinvar()` /
`settabwinvar()` take it from there. The trouble is that the tab-local and
the cross-tab calls look alike at the call site and take the same window ID,
and picking the wrong one fails silently. `winref` keeps one window-ID-keyed
surface and forbids the tab-local builtins outright — a test asserts the
source calls none of them.

## Requirements

No version gate. winref checks for the builtins it needs and disables itself
cleanly if they are missing:

```vim
if winref#available()                    " identity core: getwininfo()
if winref#available('execute')           " that plus win_execute()
if winref#available('without_equalize')  " winrestcmd()
```

On Neovim `nvim_win_get_config()` is also required by the core, because
excluding floating windows is part of the contract rather than an extra.

Verified on Vim 9.2 and Neovim 0.12.4.

## API

Popups (Vim) and floating windows (Neovim) are outside the managed domain:
they are never returned by a query and never closed.

### Query

| Function | Returns |
| --- | --- |
| `winref#get({winid})` | Info Dict, or `{}` when the window does not exist or is a popup/float |
| `winref#find({spec})` | List of info Dicts (possibly empty) |

Info Dicts always carry exactly `winid`, `tabnr`, `bufnr`, `width`, `height`.
`spec` accepts `winid`, `bufnr` and `tabnr` (`'current'` allowed); an empty
spec deliberately matches every managed window in every tab page.

`find()` is fail-closed: a non-Dict, or a key that is not one of the three,
returns `[]` rather than falling back to "match everything", so a mistyped
`bufnr` cannot hand the caller an arbitrary window it then treats as the one
it asked for.

```vim
call winref#find({})                  " every managed window
call winref#find({'buffnr': 10})      " []  -- not 'every window'
```

Neither call changes window sizes, the current window or the current tab.

### Cross-window access

| Function | Returns |
| --- | --- |
| `winref#execute({winid}, {command})` | `v:true`, or `v:false` when the window is gone or unmanaged |
| `winref#eval({winid}, {expr} [, {opts}])` | The expression's value in that window |

`execute()` is the only way to set a window-local option in another tab page.

`eval()` distinguishes the two ways it can fail: a missing window yields
`opts.default` (`{}` when unset), while an expression that fails in a window
that *does* exist propagates its error, so a typo is not mistaken for a closed
window. Pass `{'silent': 1}` for best-effort. It is reentrant and leaves no
temporary variable behind, even on an exception.

```vim
let view = winref#eval(winid, 'winsaveview()')
let h    = winref#eval(winid, 'winheight(0)', {'default': 0, 'silent': 1})
```

### Mutation

| Function | Returns |
| --- | --- |
| `winref#try_close({winid})` | `v:true` when closed |
| `winref#without_equalize({Fn})` | `Fn`'s return value |

`try_close()` returns `v:false`, without raising, when the window does not
exist, is a popup/float, or is the only managed window of its tab page —
closing the last window of the current tab raises `E444`, and closing the last
window of *another* tab would silently destroy that tab page. Any other error
(`E37` and friends, autocmd failures) propagates.

`without_equalize()` runs `Fn` with `'equalalways'` off, so a split or close
inside it does not re-equalise every window and discard the user's manual
sizes. Switching the option back on re-equalises immediately — `:set`,
`:setglobal`, `:let &g:` and `:noautocmd` all do — so the sizes are captured
after `Fn` and replayed once the option is back on. On Neovim that replay
also names floating windows, which is harmless: the capture happens after
`Fn`, so a float's recorded size is the size it already has.

The replay can only restore sizes Vim is willing to produce. Vim sometimes
leaves a tab page's windows not filling the rows available to it — after the
tabline appears or disappears, or when `'winfixheight'` blocks the row that
has to move — and re-enabling `'equalalways'` normalises that. So on such a
tab page `without_equalize()` can change a window's height even when `Fn`
did nothing. Any redraw-forcing command would have done the same; there is
no version of this guard that avoids it.

```vim
call winref#without_equalize({ -> execute('botright 15new') })
```

## Namespace

Vim resolves an autoload call by sourcing the **first** matching file on
`'runtimepath'` and stops there; it does not fall through to the next one when
the function turns out to be missing. Two plugins each shipping
`autoload/winref.vim` therefore shadow each other, and whichever loses raises
`E117` for any function the winner's copy lacks.

So winref is vendored under each host's own namespace rather than installed
once:

```
vim-winref/autoload/winref.vim           canonical source
  └─ make vendor
       host/autoload/host/winref.vim     → host#winref#get()
```

Add hosts to `VENDOR_HOSTS` in the `Makefile` as `namespace:path` and run
`make vendor`. Never edit a vendored copy.

`eval()`'s temporary global is named after the directory its copy lives in,
so two copies cannot reach for the same one.

## Development

```sh
make init        # clone pinned vim-themis / vim-vimlint / vim-vimlparser
make test        # themis, Vim
make test-nvim   # themis, Neovim
make lint        # vimlint
make vendor      # regenerate vendored copies
make vendor-check  # fail if a vendored copy is stale or hand-edited
```

## LICENSE

MIT. See [LICENSE](LICENSE).

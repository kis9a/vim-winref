" test/winref.vim: tests for autoload/winref.vim

scriptencoding utf-8

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')

let s:suite = themis#suite('winref')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  silent! tabonly!
  silent! only!
  silent! enew!
  let g:winref#test_missing = []
endfunction

function! s:suite.after_each() abort
  silent! tabonly!
  silent! only!
  let g:winref#test_missing = []
  for l:k in filter(keys(g:), 'v:val =~# "^Winref_tmp_"')
    execute 'unlet! g:' . l:k
  endfor
endfunction

" A managed window of this tab page that is not the current one.
" getwininfo()'s order depends on the split position, so [0] is not
" reliably 'the other window'.
function! s:other_win() abort
  let l:here = win_getid()
  return filter(winref#find({'tabnr': 'current'}),
        \ {_, v -> v.winid != l:here})[0].winid
endfunction

" Open a float (Neovim) or popup (Vim); returns its window ID.
function! s:open_unmanaged() abort
  if has('nvim')
    let l:b = nvim_create_buf(v:false, v:true)
    return nvim_open_win(l:b, v:false,
          \ {'relative': 'editor', 'row': 1, 'col': 1, 'width': 10, 'height': 3})
  endif
  return popup_create('x', {'line': 2, 'col': 2})
endfunction

function! s:close_unmanaged(id) abort
  if has('nvim')
    silent! call nvim_win_close(a:id, v:true)
  else
    silent! call popup_close(a:id)
  endif
endfunction

" ===========================================================================
" Capability gate
" ===========================================================================

function! s:suite.available_reports_core_and_features() abort
  call s:assert.equals(winref#available(), v:true)
  call s:assert.equals(winref#available('execute'), v:true)
  call s:assert.equals(winref#available('without_equalize'), v:true)
endfunction

function! s:suite.available_is_false_for_unknown_feature() abort
  call s:assert.equals(winref#available('no_such_feature'), v:false)
endfunction

function! s:suite.missing_core_builtin_disables_everything_without_raising() abort
  let l:winid = win_getid()
  let g:winref#test_missing = ['getwininfo']

  call s:assert.equals(winref#available(), v:false)
  call s:assert.equals(winref#available('execute'), v:false)
  " No public entry point may raise when the gate is closed
  call s:assert.equals(winref#get(l:winid), {})
  call s:assert.equals(winref#find({}), [])
  call s:assert.equals(winref#execute(l:winid, 'let g:_unused = 1'), v:false)
  call s:assert.equals(winref#eval(l:winid, '1', {'default': -1}), -1)
  call s:assert.equals(winref#try_close(l:winid), v:false)
endfunction

function! s:suite.missing_win_execute_keeps_identity_core() abort
  let l:winid = win_getid()
  let g:winref#test_missing = ['win_execute']

  call s:assert.equals(winref#available(), v:true)
  call s:assert.equals(winref#available('execute'), v:false)
  call s:assert.false(empty(winref#get(l:winid)))
  call s:assert.equals(winref#execute(l:winid, 'let g:_unused = 1'), v:false)
endfunction

function! s:suite.without_equalize_needs_no_window_query_api() abort
  let g:winref#test_missing = ['getwininfo', 'win_execute']
  call s:assert.equals(winref#available('without_equalize'), v:true)
  call s:assert.equals(winref#without_equalize({ -> 42 }), 42)
endfunction

" The size replay makes winrestcmd() a hard dependency of this feature.
function! s:suite.without_equalize_requires_winrestcmd() abort
  let g:winref#test_missing = ['winrestcmd']
  call s:assert.equals(winref#available('without_equalize'), v:false)
  call s:assert.equals(winref#available(), v:true)
  set equalalways
  call s:assert.equals(winref#without_equalize({ -> 42 }), 42)
  call s:assert.equals(&equalalways, 1)
  set noequalalways
endfunction

" ===========================================================================
" get() / find()
" ===========================================================================

function! s:suite.get_returns_dict_with_fixed_keys() abort
  let l:info = winref#get(win_getid())
  call s:assert.equals(sort(keys(l:info)),
        \ ['bufnr', 'height', 'tabnr', 'width', 'winid'])
endfunction

function! s:suite.get_returns_empty_for_bad_input() abort
  call s:assert.equals(winref#get(0), {})
  call s:assert.equals(winref#get(-1), {})
  call s:assert.equals(winref#get(999999), {})
  call s:assert.equals(winref#get('not a number'), {})
endfunction

function! s:suite.get_finds_a_window_in_another_tab() abort
  let l:winid = win_getid()
  tabnew
  " The builtins this module replaces both fail here
  call s:assert.equals(win_id2win(l:winid), 0)

  let l:info = winref#get(l:winid)
  call s:assert.equals(l:info.winid, l:winid)
  call s:assert.equals(l:info.tabnr, 1)
  call s:assert.equals(tabpagenr(), 2)
endfunction

function! s:suite.find_by_bufnr_spans_tabs() abort
  let l:bufnr = bufnr('%')
  let l:winid = win_getid()
  tabnew
  call s:assert.equals(bufwinid(l:bufnr), -1)

  let l:found = map(winref#find({'bufnr': l:bufnr}), {_, v -> v.winid})
  call s:assert.equals(index(l:found, l:winid) >= 0, 1)
  call s:assert.equals(tabpagenr(), 2)
endfunction

function! s:suite.find_by_current_tab_excludes_other_tabs() abort
  let l:tab1 = win_getid()
  tabnew
  let l:here = map(winref#find({'tabnr': 'current'}), {_, v -> v.winid})
  call s:assert.equals(index(l:here, l:tab1), -1)
  call s:assert.equals(index(l:here, win_getid()) >= 0, 1)
endfunction

function! s:suite.find_always_returns_a_list() abort
  call s:assert.equals(type(winref#find({'winid': 999999})), type([]))
  call s:assert.equals(winref#find({'winid': 999999}), [])
  call s:assert.equals(type(winref#find({})), type([]))
endfunction

" An empty spec means "everything" on purpose; a malformed one must not.
function! s:suite.find_is_fail_closed_for_a_malformed_spec() abort
  call s:assert.false(empty(winref#find({})))
  call s:assert.equals(winref#find('not a dict'), [])
  call s:assert.equals(winref#find(42), [])
  call s:assert.equals(winref#find([]), [])
  call s:assert.equals(winref#find({'buffnr': bufnr('%')}), [])
  call s:assert.equals(winref#find({'bufnr': bufnr('%'), 'typo': 1}), [])
endfunction

" A value of the wrong type is as malformed as a wrong key.  Vim refuses to
" compare a Number with a List or a Dict, so before this was rejected up
" front find({'winid': []}) raised E691 out of a function that is
" documented to always return a List.
function! s:suite.find_is_fail_closed_for_a_wrong_typed_value() abort
  call s:assert.equals(winref#find({'winid': []}), [])
  call s:assert.equals(winref#find({'bufnr': {}}), [])
  call s:assert.equals(winref#find({'tabnr': [1]}), [])
  call s:assert.equals(winref#find({'winid': 'not a number'}), [])
  call s:assert.equals(winref#find({'bufnr': v:null}), [])
  call s:assert.equals(winref#find({'tabnr': 1.5}), [])
  call s:assert.equals(winref#find({'tabnr': 'previous'}), [])
  " ... and the well-formed spec next to it still works
  call s:assert.false(empty(winref#find({'tabnr': 'current'})))
  call s:assert.false(empty(winref#find({'winid': win_getid()})))
endfunction

function! s:suite.float_or_popup_is_never_returned() abort
  let l:id = s:open_unmanaged()
  try
    call s:assert.equals(winref#get(l:id), {})
    let l:ids = map(winref#find({}), {_, v -> v.winid})
    call s:assert.equals(index(l:ids, l:id), -1)
  finally
    call s:close_unmanaged(l:id)
  endtry
endfunction

" ===========================================================================
" execute() / eval()
" ===========================================================================

function! s:suite.execute_runs_in_the_target_window() abort
  split
  let l:here = win_getid()
  let l:other = s:other_win()
  call s:assert.true(l:other != l:here)

  call s:assert.equals(winref#execute(l:other, 'let w:winref_marker = 1'), v:true)

  call s:assert.equals(winref#eval(l:other, 'get(w:, "winref_marker", 0)'), 1)
  call s:assert.equals(win_getid(), l:here)
endfunction

function! s:suite.execute_returns_false_for_missing_window() abort
  call s:assert.equals(winref#execute(999999, 'let g:_unused = 1'), v:false)
endfunction

function! s:suite.execute_sets_window_options_across_tabs() abort
  setlocal foldmethod=marker
  let l:winid = win_getid()
  tabnew
  " setwinvar() is tab-local and fails silently here
  call setwinvar(l:winid, '&foldmethod', 'indent')

  call s:assert.equals(
        \ winref#execute(l:winid, 'setlocal foldmethod=syntax'), v:true)

  tabclose
  call s:assert.equals(&foldmethod, 'syntax')
endfunction

function! s:suite.eval_reads_the_target_windows_state() abort
  call setline(1, ['a', 'b', 'c'])
  let l:first = win_getid()
  split
  call cursor(1, 1)
  let l:second = win_getid()
  call winref#execute(l:first, 'call cursor(3, 1)')

  call s:assert.equals(winref#eval(l:first, 'line(".")'), 3)
  call s:assert.equals(line('.'), 1)
  call s:assert.equals(win_getid(), l:second)
endfunction

function! s:suite.eval_missing_window_yields_default() abort
  call s:assert.equals(winref#eval(999999, 'winheight(0)', {'default': -1}), -1)
  call s:assert.equals(winref#eval(999999, 'winheight(0)'), {})
endfunction

function! s:suite.eval_propagates_an_expression_error() abort
  let l:winid = win_getid()
  let l:raised = 0
  try
    call winref#eval(l:winid, 'WinrefNoSuchFunction()')
  catch /E117/
    let l:raised = 1
  endtry
  call s:assert.equals(l:raised, 1)
endfunction

function! s:suite.eval_silent_falls_back_instead_of_raising() abort
  call s:assert.equals(
        \ winref#eval(win_getid(), 'WinrefNoSuchFunction()',
        \             {'default': 'fallback', 'silent': 1}),
        \ 'fallback')
endfunction

" The temporary is a global, and a Funcref cannot be assigned to a global
" whose name does not start with a capital (E704).  With an underscored
" name this raised, and under {'silent': 1} it returned the default --
" indistinguishable from "the window is gone".
function! s:suite.eval_returns_a_funcref() abort
  split
  let l:other = s:other_win()

  call s:assert.equals(winref#eval(l:other, 'function("tr")'), function('tr'))
  call s:assert.equals(winref#eval(l:other, '{ -> 42 }')(), 42)

  call winref#execute(l:other, 'let w:winref_fn = function("tr")')
  call s:assert.equals(winref#eval(l:other, 'w:winref_fn'), function('tr'))
  call s:assert.equals(filter(keys(g:), 'v:val =~# "^Winref_tmp_"'), [])
endfunction

function! s:suite.eval_silent_does_not_mistake_a_funcref_for_a_closed_window() abort
  split
  let l:other = s:other_win()
  call s:assert.equals(
        \ winref#eval(l:other, 'function("tr")',
        \             {'default': 'LOOKS-CLOSED', 'silent': 1}),
        \ function('tr'))
endfunction

function! s:suite.eval_leaves_no_temporary_variable() abort
  call winref#eval(win_getid(), 'winheight(0)')
  silent! call winref#eval(win_getid(), 'WinrefNoSuchFunction()', {'silent': 1})
  try
    call winref#eval(win_getid(), 'WinrefNoSuchFunction()')
  catch
  endtry
  call s:assert.equals(filter(keys(g:), 'v:val =~# "^Winref_tmp_"'), [])
endfunction

function! s:suite.eval_is_reentrant() abort
  split
  let l:other = s:other_win()
  call s:assert.true(l:other != win_getid())
  let g:winref_nested_target = l:other
  " The inner eval runs while the outer one holds a temporary of its own
  let l:got = winref#eval(win_getid(),
        \ 'winref#eval(g:winref_nested_target, "1 + 1") + 10')
  unlet g:winref_nested_target
  call s:assert.equals(l:got, 12)
  call s:assert.equals(filter(keys(g:), 'v:val =~# "^Winref_tmp_"'), [])
endfunction

" ===========================================================================
" try_close()
" ===========================================================================

function! s:suite.try_close_closes_a_window() abort
  split
  let l:target = win_getid()
  call s:assert.equals(winref#try_close(l:target), v:true)
  call s:assert.equals(winref#get(l:target), {})
endfunction

function! s:suite.try_close_is_false_for_missing_window() abort
  call s:assert.equals(winref#try_close(999999), v:false)
endfunction

function! s:suite.try_close_is_false_for_float_or_popup() abort
  split
  let l:id = s:open_unmanaged()
  try
    call s:assert.equals(winref#try_close(l:id), v:false)
  finally
    call s:close_unmanaged(l:id)
  endtry
endfunction

function! s:suite.try_close_is_false_for_the_sole_window_of_this_tab() abort
  call s:assert.equals(winnr('$'), 1)
  call s:assert.equals(winref#try_close(win_getid()), v:false)
  call s:assert.equals(winnr('$'), 1)
endfunction

function! s:suite.try_close_is_false_for_the_sole_window_of_another_tab() abort
  let l:lonely = win_getid()
  tabnew
  let l:tabs = tabpagenr('$')

  call s:assert.equals(winref#try_close(l:lonely), v:false)

  " The other tab page must survive: win_execute()ing :close there would
  " have destroyed it without raising E444
  call s:assert.equals(tabpagenr('$'), l:tabs)
  call s:assert.false(empty(winref#get(l:lonely)))
endfunction

function! s:suite.try_close_closes_a_window_in_another_tab() abort
  split
  let l:victim = win_getid()
  tabnew
  let l:tabs = tabpagenr('$')

  call s:assert.equals(winref#try_close(l:victim), v:true)

  call s:assert.equals(winref#get(l:victim), {})
  call s:assert.equals(tabpagenr('$'), l:tabs)
  call s:assert.equals(tabpagenr(), 2)
endfunction

" ===========================================================================
" without_equalize()
" ===========================================================================

function! s:suite.without_equalize_disables_and_restores() abort
  set equalalways
  call s:assert.equals(winref#without_equalize({ -> &equalalways }), 0)
  call s:assert.equals(&equalalways, 1)
endfunction

function! s:suite.without_equalize_nests() abort
  set equalalways
  function! s:inner() abort
    return winref#without_equalize({ -> &equalalways })
  endfunction
  call s:assert.equals(winref#without_equalize(function('s:inner')), 0)
  call s:assert.equals(&equalalways, 1)
endfunction

function! s:suite.without_equalize_restores_on_exception() abort
  set equalalways
  try
    call winref#without_equalize({ -> execute('throw "boom"') })
  catch /boom/
  endtry
  call s:assert.equals(&equalalways, 1)
endfunction

function! s:suite.without_equalize_keeps_manual_sizes_on_split() abort
  " 'equalalways' re-equalises the moment it is switched on, so turn it on
  " first and take the manual widths afterwards
  set equalalways
  vsplit
  vsplit
  1wincmd w
  vertical resize 20
  2wincmd w
  vertical resize 30
  let l:before = map(getwininfo(), {_, v -> v.width})

  call winref#without_equalize({ -> execute('wincmd b | rightbelow vnew') })

  let l:after = map(getwininfo(), {_, v -> v.width})
  " The two untouched windows keep their manual widths; with 'equalalways'
  " on, every window would have been re-equalised instead
  call s:assert.equals(l:after[0], l:before[0])
  call s:assert.equals(l:after[1], l:before[1])
  set noequalalways
endfunction

" Neovim's winrestcmd() lists floating windows too, and without_equalize()
" replays it verbatim.  The capture happens after Fn, so a float's recorded
" size is the size it already has -- including one Fn itself changed.
function! s:suite.without_equalize_leaves_a_float_alone() abort
  if !has('nvim')
    return
  endif
  set equalalways
  vsplit
  let l:id = s:open_unmanaged()
  try
    let l:before = nvim_win_get_config(l:id)
    call winref#without_equalize({ -> execute('wincmd b | rightbelow vnew') })
    let l:after = nvim_win_get_config(l:id)
    call s:assert.equals([l:after.width, l:after.height],
          \ [l:before.width, l:before.height])
  finally
    call s:close_unmanaged(l:id)
    set noequalalways
  endtry
endfunction

" ===========================================================================
" Cross-copy isolation (host-namespace vendoring)
" ===========================================================================

" Every vendored copy has its own s:seq, so a shared temporary name would
" have one copy reach for the other's global.  Nesting alone does not prove
" this: the inner call normally finishes while the outer's right-hand side
" is still being evaluated, so the outer assigns last and a shared name
" survives by accident.  It only breaks when an inner call runs *after* the
" outer has assigned and before it reads back -- and then only if the two
" counters happen to be at the same value.  Assert the mechanism instead:
" each copy's temporary must carry its own namespace.
function! s:suite.eval_temporaries_are_named_per_vendored_copy() abort
  let l:dir = tempname()
  call mkdir(l:dir . '/autoload/winreftesthost', 'p')
  call writefile(
        \ map(readfile(s:root . '/autoload/winref.vim'),
        \     'substitute(v:val, "winref#", "winreftesthost#winref#", "g")'),
        \ l:dir . '/autoload/winreftesthost/winref.vim')
  execute 'set runtimepath^=' . fnameescape(l:dir)
  try
    let l:winid = win_getid()
    " The bar tail runs after the temporary has been assigned, so keys(g:)
    " sees the name the copy chose for it
    let l:probe = '0 | let g:winref_seen = '
          \ . 'filter(keys(g:), ''v:val =~# "^Winref_tmp_"'')'

    call winref#eval(l:winid, l:probe)
    let l:mine = copy(g:winref_seen)
    call winreftesthost#winref#eval(l:winid, l:probe)
    let l:theirs = copy(g:winref_seen)

    call s:assert.equals(len(l:mine), 1)
    call s:assert.equals(len(l:theirs), 1)
    call s:assert.true(l:mine[0] !=# l:theirs[0])
    call s:assert.match(l:theirs[0], 'winreftesthost')
    call s:assert.equals(filter(keys(g:), 'v:val =~# "^Winref_tmp_"'), [])
  finally
    unlet! g:winref_seen
    execute 'set runtimepath-=' . fnameescape(l:dir)
    call delete(l:dir, 'rf')
  endtry
endfunction

" ===========================================================================
" Source hygiene
" ===========================================================================

function! s:suite.source_never_pairs_win_gettype_with_win_id2win() abort
  let l:hits = filter(readfile(s:root . '/autoload/winref.vim'),
        \ 'v:val !~# "^\\s*\"" && v:val =~# "win_gettype(\\s*win_id2win("')
  call s:assert.equals(l:hits, [])
endfunction

function! s:suite.source_never_calls_the_tab_local_builtins() abort
  let l:banned = 'bufwinid(\|bufwinnr(\|win_id2win(\|setwinvar(\|getwinvar('
  let l:hits = filter(readfile(s:root . '/autoload/winref.vim'),
        \ 'v:val !~# "^\\s*\"" && v:val =~# l:banned')
  call s:assert.equals(l:hits, [])
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

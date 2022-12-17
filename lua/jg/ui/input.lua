local function input_win(opts, on_confirm, win_opts)
  win_opts = win_opts or {}
  local prompt = opts.prompt or ''
  local default = opts.default or ''

  local ctx = {
    open = true,
  }
  local bufnr = vim.api.nvim_create_buf(false, true)

  vim.bo[bufnr].buftype = 'prompt'
  vim.bo[bufnr].bufhidden = 'wipe'

  vim.fn.prompt_setprompt(bufnr, '')

  local function close(value)
    if not ctx.open then
      return
    end
    ctx.open = false

    pcall(vim.api.nvim_win_close, ctx.winid, true)
    vim.defer_fn(function()
      on_confirm(value)
    end, 10)
  end

  local function confirm()
    close(vim.api.nvim_buf_get_lines(0, 0, 1, true)[1])
  end

  vim.api.nvim_create_autocmd('BufLeave', {
    desc = 'Close vim.ui.input on leave',
    buffer = bufnr,
    nested = true,
    once = true,
    callback = function()
      close()
    end,
  })

  if opts.complete then
    require('jg.ui.completefunc').attach(bufnr, opts.complete)
  end

  vim.keymap.set({ 'i', 'n' }, '<CR>', confirm, { silent = true, buffer = bufnr })
  vim.keymap.set({ 'i', 'n' }, '<ESC>', close, { silent = true, buffer = bufnr })
  vim.keymap.set({ 'i', 'n' }, '<C-c>', close, { silent = true, buffer = bufnr })

  win_opts = vim.tbl_deep_extend(
    'force',
    {
      border = 'single',
      relative = 'cursor',
      row = 1,
      col = 0,
      height = 1,
      width = 40,
      style = 'minimal',
      focusable = true,
    },
    win_opts or {},
    {
      title = ' ' .. prompt .. ' ',
    }
  )

  ctx.winid = vim.api.nvim_open_win(bufnr, true, win_opts)
  vim.api.nvim_win_set_option(ctx.winid, 'winhighlight', 'Search:None')

  vim.defer_fn(function()
    vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { default })
    vim.cmd.startinsert({ bang = true })
  end, 5)
end

return function(opts, on_confirm)
  input_win(opts, on_confirm, {})
end

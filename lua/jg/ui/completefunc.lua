local M = {}
local l = {}

local context = {}

l.completefunc = function(findstart, base)
  if findstart == 1 then
    return 0 -- the column where the completion starts
  end

  if not context.completion then
    return {}
  end

  local pieces = vim.fn.split(context.completion, ',')
  local completion = pieces[1]
  local completion_fn = pieces[2]

  if completion == 'custom' or completion == 'customlist' then
    local fn = vim.fn[completion_fn]

    if vim.startswith(completion_fn, 'v:lua.') then
      fn = loadstring(('return %s(...)'):format(completion_fn:sub(7))) or l.return_syntaxt_error
    end

    local ok, result = pcall(fn, base, base, vim.fn.strlen(base))
    if not ok then
      vim.api.nvim_err_writeln(string.format("[ui] Faild to call completion function '%s'", completion_fn))
      return {}
    end

    if completion == 'custom' then
      return vim.fn.split(result, '\n')
    end

    return result
  else
    local ok, result = pcall(vim.fn.getcompletion, base, context.completion)
    if not ok then
      vim.api.nvim_err_writeln(string.format("[ui] Unsupported completion method '%s'", completion))
      return {}
    end

    return result
  end
end

M.attach = function(bufnr, completion)
  local name = 'jg_ui_input_complete_' .. bufnr

  context.completion = completion
  _G[name] = l.completefunc

  vim.api.nvim_buf_set_option(bufnr, 'completefunc', 'v:lua.' .. name)
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', '')

  vim.keymap.set('i', '<Tab>', l.trigger_completion, { buffer = bufnr, expr = true })
  vim.keymap.set('i', '<S-Tab>', l.trigger_completion_prev, { buffer = bufnr, expr = true })

  vim.api.nvim_create_autocmd({ 'BufWipeout' }, {
    desc = 'Remove vim.ui.input completion on delete',
    buffer = bufnr,
    once = true,
    callback = function()
      context.completion = nil
      _G[name] = nil
    end,
  })
end

l.return_syntaxt_error = function()
  error('Syntax error')
end

l.trigger_completion = function()
  if vim.fn.pumvisible() == 1 then
    return '<C-n>'
  else
    return '<C-x><C-u>'
  end
end

l.trigger_completion_prev = function()
  if vim.fn.pumvisible() == 1 then
    return '<C-p>'
  end
end

return M

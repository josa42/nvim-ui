local config = {
  -- When true, <Esc> will close the modal
  insert_only = true,

  -- When true, input will start in insert mode.
  start_in_insert = true,

  -- These are passed to nvim_open_win
  anchor = 'NW',
  border = 'rounded',
  -- 'editor' and 'win' will default to being centered
  relative = 'cursor',

  -- These can be integers or a float between 0 and 1 (e.g. 0.4 for 40%)
  prefer_width = 40,
  width = nil,
  -- min_width and max_width can be a list of mixed types.
  -- min_width = {20, 0.2} means "the greater of 20 columns or 20% of total"
  max_width = { 140, 0.9 },
  min_width = { 20, 0.2 },
}
-- local patch = require('dressing.patch')

--------------------------------------------------------------------------------
-- util
local winid_map = {}
local function is_float(value)
  local _, p = math.modf(value)
  return p ~= 0
end

local function calc_float(value, max_value)
  if value and is_float(value) then
    return math.min(max_value, value * max_value)
  else
    return value
  end
end

local function calc_list(values, max_value, aggregator, limit)
  local ret = limit
  if type(values) == 'table' then
    for _, v in ipairs(values) do
      ret = aggregator(ret, calc_float(v, max_value))
    end
    return ret
  else
    ret = aggregator(ret, calc_float(values, max_value))
  end
  return ret
end

local function calculate_dim(desired_size, size, min_size, max_size, total_size)
  local ret = calc_float(size, total_size)
  local min_val = calc_list(min_size, total_size, math.max, 1)
  local max_val = calc_list(max_size, total_size, math.min, total_size)
  if not ret then
    if not desired_size then
      ret = (min_val + max_val) / 2
    else
      ret = calc_float(desired_size, total_size)
    end
  end
  ret = math.min(ret, max_val)
  ret = math.max(ret, min_val)
  return math.floor(ret)
end

local function get_max_width(relative, winid)
  if relative == 'editor' then
    return vim.o.columns
  else
    return vim.api.nvim_win_get_width(winid or 0)
  end
end

local function get_max_height(relative, winid)
  if relative == 'editor' then
    return vim.o.lines - vim.o.cmdheight
  else
    return vim.api.nvim_win_get_height(winid or 0)
  end
end

local function calculate_col(relative, width, winid)
  if relative == 'cursor' then
    return 0
  else
    return math.floor((get_max_width(relative, winid) - width) / 2)
  end
end

local function calculate_row(relative, height, winid)
  if relative == 'cursor' then
    return 0
  else
    return math.floor((get_max_height(relative, winid) - height) / 2)
  end
end

local function calculate_width(relative, desired_width, winid)
  return calculate_dim(desired_width, config.width, config.min_width, config.max_width, get_max_width(relative, winid))
end

local function add_title_to_win(winid, title, opts)
  opts = opts or {}
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  -- HACK to force the parent window to position itself
  -- See https://github.com/neovim/neovim/issues/13403
  vim.cmd.redraw()
  local width = math.min(vim.api.nvim_win_get_width(winid) - 4, 2 + vim.api.nvim_strwidth(title))
  local title_winid = winid_map[winid]
  local bufnr
  if title_winid and vim.api.nvim_win_is_valid(title_winid) then
    vim.api.nvim_win_set_width(title_winid, width)
    bufnr = vim.api.nvim_win_get_buf(title_winid)
  else
    bufnr = vim.api.nvim_create_buf(false, true)

    title_winid = vim.api.nvim_open_win(bufnr, false, {
      relative = 'win',
      win = winid,
      width = width,
      height = 1,
      row = -1,
      col = 1,
      focusable = false,
      zindex = 151,
      style = 'minimal',
      noautocmd = true,
    })
    winid_map[winid] = title_winid
    vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
    vim.cmd(string.format([[ autocmd WinClosed %d ++once lua require('jg.ui.input').remove_title(%d) ]], winid, winid))
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { ' ' .. title .. ' ' })
  local ns = vim.api.nvim_create_namespace('DressingWindow')
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, ns, 'FloatTitle', 0, 0, -1)
end

local M = {}

M.remove_title = function(winid)
  local title_winid = winid_map[winid]
  if title_winid and vim.api.nvim_win_is_valid(title_winid) then
    vim.api.nvim_win_close(title_winid, true)
  end
  winid_map[winid] = nil
end

local context = {
  opts = nil,
  on_confirm = nil,
  winid = nil,
  start_in_insert = nil,
}

local function close_completion_window()
  if vim.fn.pumvisible() == 1 then
    local escape_key = vim.api.nvim_replace_termcodes('<C-e>', true, false, true)
    vim.api.nvim_feedkeys(escape_key, 'n', true)
  end
end

local function confirm(text)
  if not context.on_confirm then
    return
  end
  close_completion_window()
  local ctx = context
  context = {}
  if not ctx.start_in_insert then
    vim.cmd('stopinsert')
  end
  -- We have to wait briefly for the popup window to close (if present),
  -- otherwise vim gets into a very weird and bad state. I was seeing text get
  -- deleted from the buffer after the input window closes.
  vim.defer_fn(function()
    pcall(vim.api.nvim_win_close, ctx.winid, true)
    if text == '' then
      text = nil
    end
    -- Defer the callback because we just closed windows and left insert mode.
    -- In practice from my testing, if the user does something right now (like,
    -- say, opening another input modal) it could happen improperly. I was
    -- seeing my successive modals fail to enter insert mode.
    vim.defer_fn(function()
      ctx.on_confirm(text)
    end, 5)
  end, 5)
end

M.confirm = function()
  local text = vim.api.nvim_buf_get_lines(0, 0, 1, true)[1]
  confirm(text)
end

M.close = function()
  confirm(context.opts and context.opts.cancelreturn)
end

M.completefunc = function(findstart, base)
  if findstart == 1 then
    return 0
  elseif not context.opts or not context.opts.completion then
    return {}
  else
    local completion = context.opts.completion
    local pieces = vim.fn.split(completion, ',')
    if pieces[1] == 'custom' or pieces[1] == 'customlist' then
      local vim_fn = pieces[2]
      local fn = vim.fn[vim_fn]

      if vim.startswith(vim_fn, 'v:lua.') then
        local luafunc, err = loadstring(('return %s(...)'):format(vim_fn:sub(7)))
        if err ~= nil then
          vim.api.nvim_err_writeln(string.format('Could not find completion function %s: %s', vim_fn, err))
          return {}
        end
        fn = luafunc
      end

      if not fn then
        return {}
      end

      local ok, result = pcall(fn, base, base, vim.fn.strlen(base))
      if not ok then
        vim.api.nvim_err_writeln(string.format("Faild to call completion method '%s'", completion))
        return {}
      end

      if pieces[1] == 'custom' then
        return vim.fn.split(result, '\n')
      end

      return result
    else
      local ok, result = pcall(vim.fn.getcompletion, base, context.opts.completion)
      if ok then
        return result
      else
        vim.api.nvim_err_writeln(string.format("Unsupported completion method '%s'", completion))
        return {}
      end
    end
  end
end

_G.jg_ui_input_complete = M.completefunc

M.trigger_completion = function()
  if vim.fn.pumvisible() == 1 then
    return '<C-n>'
  else
    return '<C-x><C-u>'
  end
end

local function create_win(prompt, opts)
  -- close still open window
  if context.winid and vim.api.nvim_win_is_valid(context.winid) then
    vim.api.nvim_win_close(context.winid, true)
  end

  -- First calculate the desired base width of the modal
  -- Then expand the width to fit the prompt and default value
  local prefer_width = math.max(
    calculate_width(config.relative, config.prefer_width, 0),
    4 + vim.api.nvim_strwidth(prompt or ''),
    2 + vim.api.nvim_strwidth(opts.default or '')
  )
  local width = calculate_width(config.relative, prefer_width, 0)

  local start_in_insert = string.sub(vim.api.nvim_get_mode().mode, 1, 1) == 'i'
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = config.relative,
    anchor = config.anchor,
    border = config.border,
    height = 1,
    style = 'minimal',
    noautocmd = true,
    row = calculate_row(config.relative, 1, 0),
    col = calculate_col(config.relative, width, 0),
    width = width,
  })

  return winid, start_in_insert
end

setmetatable(M, {
  -- use schedule_wrap to avoid a bug when vim opens
  -- (see https://github.com/stevearc/dressing.nvim/issues/15)
  __call = vim.schedule_wrap(function(_, opts, on_confirm)
    vim.validate({
      on_confirm = { on_confirm, 'function', false },
    })
    opts = opts or {}
    if type(opts) ~= 'table' then
      opts = { prompt = tostring(opts) }
    end

    -- Create or update the window
    local prompt = opts.prompt

    local winid, start_in_insert = create_win(prompt, opts)
    context = {
      winid = winid,
      on_confirm = on_confirm,
      opts = opts,
      start_in_insert = start_in_insert,
    }
    vim.api.nvim_win_set_option(winid, 'wrap', false)
    local bufnr = vim.api.nvim_win_get_buf(winid)

    -- Finish setting up the buffer
    vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
    vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')

    vim.keymap.set({ 'i', 'n' }, '<CR>', M.confirm, { buffer = bufnr })
    vim.keymap.set({ 'n' }, '<Esc>', M.close, { buffer = bufnr })
    vim.keymap.set({ 'i' }, '<C-c>', M.close, { buffer = bufnr })

    if config.insert_only then
      vim.keymap.set('i', '<Esc>', M.close, { buffer = bufnr })
    end

    vim.api.nvim_buf_set_option(bufnr, 'filetype', 'ui-input')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { opts.default or '' })

    -- Disable nvim-cmp if installed
    local ok, cmp = pcall(require, 'cmp')
    if ok then
      cmp.setup.buffer({ enabled = false })
    end
    -- Disable mini.nvim completion if installed
    vim.api.nvim_buf_set_var(bufnr, 'minicompletion_disable', true)

    if prompt then
      add_title_to_win(winid, string.gsub(prompt, '^%s*(.-)%s*$', '%1'))
    else
      M.remove_title(winid)
    end

    if opts.completion then
      vim.api.nvim_buf_set_option(bufnr, 'completefunc', 'v:lua.jg_ui_input_complete')
      vim.api.nvim_buf_set_option(bufnr, 'omnifunc', '')
      vim.keymap.set('i', '<Tab>', M.trigger_completion, { buffer = bufnr, expr = true })
    end

    vim.api.nvim_create_autocmd('BufLeave', {
      desc = 'Cancel vim.ui.input',
      buffer = bufnr,
      nested = true,
      once = true,
      callback = M.close,
    })

    if config.start_in_insert then
      vim.cmd('startinsert!')
    end
    close_completion_window()
  end),
})

return M

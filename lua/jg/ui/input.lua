local map_util = {
  create_plug_maps = function(bufnr, plug_bindings)
    for _, binding in ipairs(plug_bindings) do
      vim.keymap.set('', binding.plug, binding.rhs, { buffer = bufnr, desc = binding.desc })
    end
  end,
  create_maps_to_plug = function(bufnr, mode, bindings, prefix)
    local maps
    if mode == 'i' then
      maps = vim.api.nvim_buf_get_keymap(bufnr, '')
    end
    for lhs, rhs in pairs(bindings) do
      if rhs then
        -- Prefix with <Plug> unless this is a <Cmd> or :Cmd mapping
        if type(rhs) == 'string' and not rhs:match('[<:]') then
          rhs = '<Plug>' .. prefix .. rhs
        end
        if mode == 'i' then
          -- HACK for some reason I can't get plug mappings to work in insert mode
          for _, map in ipairs(maps) do
            if map.lhs == rhs then
              rhs = map.callback or map.rhs
              break
            end
          end
        end
        vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, remap = true })
      end
    end
  end,
}

local global_config = {
  get_mod_config = function()
    return {
      -- Default prompt string
      default_prompt = 'Input:',

      -- Can be 'left', 'right', or 'center'
      prompt_align = 'left',

      -- When true, <Esc> will close the modal
      insert_only = true,

      -- When true, input will start in insert mode.
      start_in_insert = true,

      -- These are passed to nvim_open_win
      anchor = 'SW',
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

      -- Window transparency (0-100)
      winblend = 10,
      -- Change default highlight groups (see :help winhl)
      winhighlight = '',

      -- Set to `false` to disable
      mappings = {
        n = {
          ['<Esc>'] = 'Close',
          ['<CR>'] = 'Confirm',
        },
        i = {
          ['<C-c>'] = 'Close',
          ['<CR>'] = 'Confirm',
          ['<Up>'] = 'HistoryPrev',
          ['<Down>'] = 'HistoryNext',
        },
      },

      override = function(conf)
        -- This is the config that will be passed to nvim_open_win.
        -- Change values here to customize the layout
        return conf
      end,
    }
  end,
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
local util = {
  calculate_col = function(relative, width, winid)
    if relative == 'cursor' then
      return 0
    else
      return math.floor((get_max_width(relative, winid) - width) / 2)
    end
  end,

  calculate_row = function(relative, height, winid)
    if relative == 'cursor' then
      return 0
    else
      return math.floor((get_max_height(relative, winid) - height) / 2)
    end
  end,

  calculate_width = function(relative, desired_width, config, winid)
    return calculate_dim(
      desired_width,
      config.width,
      config.min_width,
      config.max_width,
      get_max_width(relative, winid)
    )
  end,
  schedule_wrap_before_vimenter = function(func)
    return function(...)
      if vim.v.vim_did_enter == 0 then
        return vim.schedule_wrap(func)(...)
      else
        return func(...)
      end
    end
  end,

  add_title_to_win = function(winid, title, opts)
    opts = opts or {}
    opts.align = opts.align or 'center'
    if not vim.api.nvim_win_is_valid(winid) then
      return
    end
    -- HACK to force the parent window to position itself
    -- See https://github.com/neovim/neovim/issues/13403
    vim.cmd('redraw')
    local width = math.min(vim.api.nvim_win_get_width(winid) - 4, 2 + vim.api.nvim_strwidth(title))
    local title_winid = winid_map[winid]
    local bufnr
    if title_winid and vim.api.nvim_win_is_valid(title_winid) then
      vim.api.nvim_win_set_width(title_winid, width)
      bufnr = vim.api.nvim_win_get_buf(title_winid)
    else
      bufnr = vim.api.nvim_create_buf(false, true)
      local col = 1
      if opts.align == 'center' then
        col = math.floor((vim.api.nvim_win_get_width(winid) - width) / 2)
      elseif opts.align == 'right' then
        col = vim.api.nvim_win_get_width(winid) - 1 - width
      elseif opts.align ~= 'left' then
        vim.notify(string.format("Unknown dressing window title alignment: '%s'", opts.align), vim.log.levels.ERROR)
      end
      title_winid = vim.api.nvim_open_win(bufnr, false, {
        relative = 'win',
        win = winid,
        width = width,
        height = 1,
        row = -1,
        col = col,
        focusable = false,
        zindex = 151,
        style = 'minimal',
        noautocmd = true,
      })
      winid_map[winid] = title_winid
      vim.api.nvim_win_set_option(title_winid, 'winblend', vim.api.nvim_win_get_option(winid, 'winblend'))
      vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
      vim.cmd(string.format(
        [[
      autocmd WinClosed %d ++once lua require('jg.ui.input')._on_win_closed(%d)
    ]],
        winid,
        winid
      ))
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { ' ' .. title .. ' ' })
    local ns = vim.api.nvim_create_namespace('DressingWindow')
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    vim.api.nvim_buf_add_highlight(bufnr, ns, 'FloatTitle', 0, 0, -1)
  end,
}

util._on_win_closed = function(winid)
  local title_winid = winid_map[winid]
  if title_winid and vim.api.nvim_win_is_valid(title_winid) then
    vim.api.nvim_win_close(title_winid, true)
  end
  winid_map[winid] = nil
end

local M = {}

M._on_win_closed = util._on_win_closed

local context = {
  opts = nil,
  on_confirm = nil,
  winid = nil,
  history_idx = nil,
  history_tip = nil,
  start_in_insert = nil,
}

local keymaps = {
  {
    desc = 'Close vim.ui.input without a result',
    plug = '<Plug>DressingInput:Close',
    rhs = function()
      M.close()
    end,
  },
  {
    desc = 'Close vim.ui.input with the current buffer contents',
    plug = '<Plug>DressingInput:Confirm',
    rhs = function()
      M.confirm()
    end,
  },
  {
    desc = 'Show previous vim.ui.input history entry',
    plug = '<Plug>DressingInput:HistoryPrev',
    rhs = function()
      M.history_prev()
    end,
  },
  {
    desc = 'Show next vim.ui.input history entry',
    plug = '<Plug>DressingInput:HistoryNext',
    rhs = function()
      M.history_next()
    end,
  },
}

local function set_input(text)
  vim.api.nvim_buf_set_lines(0, 0, -1, true, { text })
  vim.api.nvim_win_set_cursor(0, { 1, vim.api.nvim_strwidth(text) })
end
local history = {}
M.history_prev = function()
  if context.history_idx == nil then
    if #history == 0 then
      return
    end
    context.history_tip = vim.api.nvim_buf_get_lines(0, 0, 1, true)[1]
    context.history_idx = #history
  elseif context.history_idx == 1 then
    return
  else
    context.history_idx = context.history_idx - 1
  end
  set_input(history[context.history_idx])
end
M.history_next = function()
  if not context.history_idx then
    return
  elseif context.history_idx == #history then
    context.history_idx = nil
    set_input(context.history_tip)
  else
    context.history_idx = context.history_idx + 1
    set_input(history[context.history_idx])
  end
end

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
    if text and history[#history] ~= text then
      table.insert(history, text)
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

M.highlight = function()
  if not context.opts then
    return
  end
  local bufnr = vim.api.nvim_win_get_buf(context.winid)
  local opts = context.opts
  local text = vim.api.nvim_buf_get_lines(bufnr, 0, 1, true)[1]
  local ns = vim.api.nvim_create_namespace('DressingHighlight')
  local highlights = {}
  if type(opts.highlight) == 'function' then
    highlights = opts.highlight(text)
  elseif opts.highlight then
    highlights = vim.fn[opts.highlight](text)
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, highlight in ipairs(highlights) do
    local start = highlight[1]
    local stop = highlight[2]
    local group = highlight[3]
    vim.api.nvim_buf_add_highlight(bufnr, ns, group, 0, start, stop)
  end
end

local function split(string, pattern)
  local ret = {}
  for token in string.gmatch(string, '[^' .. pattern .. ']+') do
    table.insert(ret, token)
  end
  return ret
end

M.completefunc = function(findstart, base)
  if not context.opts or not context.opts.completion then
    return findstart == 1 and 0 or {}
  end
  if findstart == 1 then
    return 0
  else
    local completion = context.opts.completion
    local pieces = split(completion, ',')
    if pieces[1] == 'custom' or pieces[1] == 'customlist' then
      local vimfunc = pieces[2]
      local ret
      if vim.startswith(vimfunc, 'v:lua.') then
        local load_func = string.format('return %s(...)', vimfunc:sub(7))
        local luafunc, err = loadstring(load_func)
        if not luafunc then
          vim.api.nvim_err_writeln(string.format('Could not find completion function %s: %s', vimfunc, err))
          return {}
        end
        ret = luafunc(base, base, vim.fn.strlen(base))
      else
        ret = vim.fn[vimfunc](base, base, vim.fn.strlen(base))
      end
      if pieces[1] == 'custom' then
        ret = split(ret, '\n')
      end
      return ret
    else
      local ok, result = pcall(vim.fn.getcompletion, base, context.opts.completion)
      if ok then
        return result
      else
        vim.api.nvim_err_writeln(string.format("dressing.nvim: unsupported completion method '%s'", completion))
        return {}
      end
    end
  end
end

_G.dressing_input_complete = M.completefunc

M.trigger_completion = function()
  if vim.fn.pumvisible() == 1 then
    return '<C-n>'
  else
    return '<C-x><C-u>'
  end
end

local function create_or_update_win(config, prompt, opts)
  local parent_win = 0
  local winopt
  local win_conf
  -- If the previous window is still open and valid, we're going to update it
  if context.winid and vim.api.nvim_win_is_valid(context.winid) then
    win_conf = vim.api.nvim_win_get_config(context.winid)
    parent_win = win_conf.win
    winopt = {
      relative = win_conf.relative,
      win = win_conf.win,
    }
  else
    winopt = {
      relative = config.relative,
      anchor = config.anchor,
      border = config.border,
      height = 1,
      style = 'minimal',
      noautocmd = true,
    }
  end
  -- First calculate the desired base width of the modal
  local prefer_width = util.calculate_width(config.relative, config.prefer_width, config, parent_win)
  -- Then expand the width to fit the prompt and default value
  prefer_width = math.max(prefer_width, 4 + vim.api.nvim_strwidth(prompt))
  if opts.default then
    prefer_width = math.max(prefer_width, 2 + vim.api.nvim_strwidth(opts.default))
  end
  -- Then recalculate to clamp final value to min/max
  local width = util.calculate_width(config.relative, prefer_width, config, parent_win)
  winopt.row = util.calculate_row(config.relative, 1, parent_win)
  winopt.col = util.calculate_col(config.relative, width, parent_win)
  winopt.width = width

  if win_conf and config.relative == 'cursor' then
    -- If we're cursor-relative we should actually not adjust the row/col to
    -- prevent jumping. Also remove related args.
    if config.relative == 'cursor' then
      winopt.row = nil
      winopt.col = nil
      winopt.relative = nil
      winopt.win = nil
    end
  end

  winopt = config.override(winopt) or winopt

  -- If the floating win was already open
  if win_conf then
    -- Make sure the previous on_confirm callback is called with nil
    vim.schedule(context.on_confirm)
    vim.api.nvim_win_set_config(context.winid, winopt)
    local start_in_insert = context.start_in_insert
    return context.winid, start_in_insert
  else
    local start_in_insert = string.sub(vim.api.nvim_get_mode().mode, 1, 1) == 'i'
    local bufnr = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_open_win(bufnr, true, winopt)
    return winid, start_in_insert
  end
end

setmetatable(M, {
  -- use schedule_wrap to avoid a bug when vim opens
  -- (see https://github.com/stevearc/dressing.nvim/issues/15)
  __call = util.schedule_wrap_before_vimenter(function(_, opts, on_confirm)
    vim.validate({
      on_confirm = { on_confirm, 'function', false },
    })
    opts = opts or {}
    if type(opts) ~= 'table' then
      opts = { prompt = tostring(opts) }
    end
    local config = global_config.get_mod_config()
    -- if not config.enabled then
    --   return patch.original_mods.input(opts, on_confirm)
    -- end
    if vim.fn.hlID('DressingInputText') ~= 0 then
      vim.notify(
        'DressingInputText highlight group is deprecated. Set winhighlight="NormalFloat:MyHighlightGroup" instead',
        vim.log.levels.WARN
      )
    end

    -- Create or update the window
    local prompt = opts.prompt or config.default_prompt

    local winid, start_in_insert = create_or_update_win(config, prompt, opts)
    context = {
      winid = winid,
      on_confirm = on_confirm,
      opts = opts,
      history_idx = nil,
      start_in_insert = start_in_insert,
    }
    vim.api.nvim_win_set_option(winid, 'winblend', config.winblend)
    vim.api.nvim_win_set_option(winid, 'winhighlight', config.winhighlight)
    vim.api.nvim_win_set_option(winid, 'wrap', false)
    local bufnr = vim.api.nvim_win_get_buf(winid)

    -- Finish setting up the buffer
    vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
    vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')

    map_util.create_plug_maps(bufnr, keymaps)
    for mode, user_maps in pairs(config.mappings) do
      map_util.create_maps_to_plug(bufnr, mode, user_maps, 'DressingInput:')
    end

    if config.insert_only then
      vim.keymap.set('i', '<Esc>', M.close, { buffer = bufnr })
    end

    vim.api.nvim_buf_set_option(bufnr, 'filetype', 'DressingInput')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { opts.default or '' })
    -- Disable nvim-cmp if installed
    local ok, cmp = pcall(require, 'cmp')
    if ok then
      cmp.setup.buffer({ enabled = false })
    end
    -- Disable mini.nvim completion if installed
    vim.api.nvim_buf_set_var(bufnr, 'minicompletion_disable', true)
    util.add_title_to_win(winid, string.gsub(prompt, '^%s*(.-)%s*$', '%1'), { align = config.prompt_align })

    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      desc = 'Update highlights',
      buffer = bufnr,
      callback = M.highlight,
    })

    if opts.completion then
      vim.api.nvim_buf_set_option(bufnr, 'completefunc', 'v:lua.dressing_input_complete')
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
    M.highlight()
  end),
})

return M
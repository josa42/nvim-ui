local M = {}

function M.setup(opts)
  opts = vim.tbl_extend('keep', opts, {
    input = true,
    select = false,
  })

  if opts.input then
    vim.ui.input = require('jg.ui.input')
  end
  if opts.select then
    vim.ui.select = require('jg.ui.select')
  end
end

return M

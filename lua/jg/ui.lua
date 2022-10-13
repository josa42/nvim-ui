local M = {}

function M.setup()
  vim.ui.input = require('jg.ui.input')
  vim.ui.select = require('jg.ui.select')
end

return M

local M = {
  base = {},
  ours = {},
  remote = {},
  merged = {},

  opts = {
    wrap = false,
  },
}

local CONFLICT_MARKER_START = '<<<<<<<'
local CONFLICT_MARKER_MARK = '======='
local CONFLICT_MARKER_END = '>>>>>>>'

local use_diff = function(diff)
  local current = vim.fn.winnr()

  vim.cmd(diff.winnr .. 'wincmd w')

  vim.cmd 'diffput'

  vim.cmd(current .. 'wincmd w')
end

M.use_1 = function()
  return use_diff(M.ours)
end

M.use_2 = function()
  return use_diff(M.remote)
end

M.close = function()
  if M.opts.post_hook ~= nil then
    M.opts.post_hook()
  end
  vim.cmd [[ wqa ]]
end

M.start = function()
  -- Set default options
  vim.opt.wrap = M.opts.wrap

  if M.opts.pre_hook ~= nil then
    M.opts.pre_hook()
  end

  local buffers = vim.api.nvim_list_bufs()

  M.base.buffer = buffers[1]
  M.ours.buffer = buffers[2]
  M.remote.buffer = buffers[3]
  M.merged.buffer = buffers[4]

  M.base.window = vim.api.nvim_get_current_win()
  M.base.winnr = 1
  vim.api.nvim_win_set_buf(M.base.window, M.base.buffer)

  vim.cmd 'botright split'
  M.ours.window = vim.api.nvim_get_current_win()
  M.ours.winnr = 2
  vim.api.nvim_win_set_buf(M.ours.window, M.ours.buffer)
  vim.cmd 'rightbelow vsplit'
  M.remote.window = vim.api.nvim_get_current_win()
  M.remote.winnr = 3
  vim.api.nvim_win_set_buf(M.remote.window, M.remote.buffer)

  vim.cmd 'botright split'
  M.merged.window = vim.api.nvim_get_current_win()
  M.merged.winnr = 4
  vim.api.nvim_win_set_buf(M.merged.window, M.merged.buffer)
  local filetype = vim.api.nvim_buf_get_option(M.merged.buffer, 'filetype')

  local lines = {}
  local in_conflict = false
  for _, line in ipairs(vim.api.nvim_buf_get_lines(M.merged.buffer, 0, -1, true)) do
    if string.find(line, CONFLICT_MARKER_START) then
      in_conflict = true
    elseif in_conflict then
      if string.find(line, CONFLICT_MARKER_MARK) then
        table.insert(lines, line)
      end

      if string.find(line, CONFLICT_MARKER_END) then
        in_conflict = false
      end
    else
      table.insert(lines, line)
    end
  end

  vim.api.nvim_buf_set_lines(M.merged.buffer, 0, -1, true, lines)

  for _, file in ipairs { M.base, M.ours, M.remote } do
    vim.api.nvim_buf_set_option(file.buffer, 'filetype', filetype)
    vim.api.nvim_buf_set_option(file.buffer, 'swapfile', false)
    vim.api.nvim_buf_set_option(file.buffer, 'modifiable', false)
  end

  vim.cmd [[ windo diffthis ]]
end

M.setup = function(opts)
  if opts ~= nil then
    for key, value in pairs(opts) do
      M.opts[key] = value
    end
  end

  vim.api.nvim_add_user_command('MergeInit', M.start, {})
  vim.api.nvim_add_user_command('MergeUse1', M.use_1, {})
  vim.api.nvim_add_user_command('MergeUse2', M.use_2, {})
  vim.api.nvim_add_user_command('MergeClose', M.close, {})

  -- splice compatible mappings
  vim.api.nvim_set_keymap('n', '-n', ']c', { silent = true })
  vim.api.nvim_set_keymap('n', '-N', '[c', { silent = true })
  vim.api.nvim_set_keymap('n', '-u1', '', { silent = true, callback = M.use_1, desc = 'Use changes from 1 (local)' })
  vim.api.nvim_set_keymap('n', '-u2', '', { silent = true, callback = M.use_2, desc = 'Use changes from 2 (remote)' })
  vim.api.nvim_set_keymap('n', '-q', '', { silent = true, callback = M.close, desc = 'Save all changes and close' })
end

return M

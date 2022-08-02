local M = {
  base = {},
  ours = {},
  remote = {},
  merged = {},

  marks = {},
  resolutions = {},

  opts = {
    wrap = false,
    symbol = '>',
    keymaps = {
      next_conflict = '-n',
      prev_conflict = '-N',
      use_ours = '-u1',
      use_theirs = '-u2',
      close = '-q',
    },
  },
}

local CONFLICT_MARKER_START = '<<<<<<<'
local CONFLICT_MARKER_MARK = '======='
local CONFLICT_MARKER_END = '>>>>>>>'

local ns_marks = vim.api.nvim_create_namespace 'settle.marks'
local ns_resolutions = vim.api.nvim_create_namespace 'settle.resolutions'

local get_mark = function(ns, level)
  if not level then
    level = vim.log.levels.ERROR
  end

  local pos = vim.api.nvim_win_get_cursor(M.merged.window)
  local mark = vim.api.nvim_buf_get_extmarks(M.merged.buffer, ns, { pos[1] - 1, 0 }, -1, {})

  if #mark == 0 then
    vim.notify('No markers found', level, {})
    return
  end

  if mark[1][2] ~= (pos[1] - 1) then
    vim.notify('Not on a marker', level, {})
    return
  end

  return mark
end

local use_diff = function(diff)
  local mark = get_mark(ns_marks)

  if not mark then
    return
  end

  local id = mark[1][1]

  local lines = M.marks[id][diff]
  vim.api.nvim_buf_set_lines(M.merged.buffer, mark[1][2], mark[1][2] + 1, false, lines)

  -- Remove conflict text
  vim.api.nvim_buf_set_extmark(M.merged.buffer, ns_marks, mark[1][2], 0, { id = id, virt_text = {} })

  vim.api.nvim_buf_set_extmark(
    M.merged.buffer,
    ns_resolutions,
    mark[1][2],
    0,
    { end_line = mark[1][2] + #lines, id = id, virt_text = { { 'Using ' .. diff, 'Comment' } } }
  )
end

M.resolve_manual = function(...)
  local mark = get_mark(ns_marks, vim.log.levels.TRACE)
  if not mark then
    return
  end

  vim.api.nvim_buf_set_extmark(M.merged.buffer, ns_marks, mark[1][2], 0, { id = mark[1][1], virt_text = {} })
  vim.api.nvim_buf_set_extmark(
    M.merged.buffer,
    ns_resolutions,
    mark[1][2],
    0,
    { id = mark[1][1], virt_text = { { 'Manual', 'Comment' } } }
  )
end

M.use_1 = function()
  return use_diff 'ours'
end

M.use_2 = function()
  return use_diff 'theirs'
end

M.next_diff = function()
  local pos = vim.api.nvim_win_get_cursor(M.merged.window)
  local mark = vim.api.nvim_buf_get_extmarks(M.merged.buffer, ns_marks, { pos[1] - 1, pos[2] }, -1, {})

  if #mark == 0 then
    return
  end

  local next_line = nil
  -- if current line is first mark, move to second, if exists
  if mark[1][2] == (pos[1] - 1) then
    if #mark > 1 then
      next_line = mark[2][2]
    end
  else
    next_line = mark[1][2]
  end

  if next_line ~= nil then
    vim.api.nvim_win_set_cursor(M.merged.window, { next_line + 1, 0 })
  else
    vim.notify('Last conflict in document', vim.log.levels.WARN, {})
  end
end

M.prev_diff = function()
  local pos = vim.api.nvim_win_get_cursor(M.merged.window)
  local mark = vim.api.nvim_buf_get_extmarks(M.merged.buffer, ns_marks, pos, 0, {})

  if #mark == 0 then
    return
  end

  local next_line = nil
  -- if current line is first mark, move to second, if exists
  if mark[1][2] == (pos[1] - 1) then
    if #mark > 1 then
      next_line = mark[2][2]
    end
  else
    next_line = mark[1][2]
  end

  if next_line ~= nil then
    vim.api.nvim_win_set_cursor(M.merged.window, { next_line + 1, 0 })
  else
    vim.notify('First conflict in document', vim.log.levels.WARN, {})
  end
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
  vim.cmd [[ keepalt file BASE ]]

  vim.cmd 'botright split'
  M.ours.window = vim.api.nvim_get_current_win()
  M.ours.winnr = 2
  vim.api.nvim_win_set_buf(M.ours.window, M.ours.buffer)
  vim.cmd [[ keepalt file OURS ]]

  vim.cmd 'rightbelow vsplit'
  M.remote.window = vim.api.nvim_get_current_win()
  M.remote.winnr = 3
  vim.api.nvim_win_set_buf(M.remote.window, M.remote.buffer)
  vim.cmd [[ keepalt file THEIRS ]]

  vim.cmd 'botright split'
  M.merged.window = vim.api.nvim_get_current_win()
  M.merged.winnr = 4
  vim.api.nvim_win_set_buf(M.merged.window, M.merged.buffer)
  local filetype = vim.api.nvim_buf_get_option(M.merged.buffer, 'filetype')

  local lines = {}
  local in_conflict = false
  local line_count = 0
  local id = 1

  local mark = nil
  local key = nil

  for _, line in ipairs(vim.api.nvim_buf_get_lines(M.merged.buffer, 0, -1, true)) do
    if string.find(line, CONFLICT_MARKER_START) then
      mark = {
        line = nil,
        id = id,
        ours = {},
        theirs = {},
      }
      in_conflict = true
      key = 'ours'
    elseif in_conflict then
      if string.find(line, CONFLICT_MARKER_MARK) then
        table.insert(lines, '')
        mark.line = line_count
        line_count = line_count + 1

        M.marks[id] = mark
        id = id + 1
        key = 'theirs'
      elseif string.find(line, CONFLICT_MARKER_END) then
        in_conflict = false
      else
        table.insert(mark[key], line)
      end
    else
      line_count = line_count + 1
      table.insert(lines, line)
    end
  end

  vim.api.nvim_buf_set_lines(M.merged.buffer, 0, -1, true, lines)

  for _, mark in pairs(M.marks) do
    vim.api.nvim_buf_set_extmark(M.merged.buffer, ns_marks, mark.line, 0, {
      virt_text = { { '< CONFLICT >', 'Error' } },
      id = mark.id,
      sign_text = M.opts.symbol,
      sign_hl_group = 'DiagnosticSignError',
    })
  end

  local group = vim.api.nvim_create_augroup('settle', {})
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    buffer = M.merged.buffer,
    desc = 'Update resolution marks when leaving insert mode',
    callback = M.resolve_manual,
  })

  for _, file in ipairs { M.base, M.ours, M.remote } do
    vim.api.nvim_buf_set_option(file.buffer, 'filetype', filetype)
    vim.api.nvim_buf_set_option(file.buffer, 'swapfile', false)
    vim.api.nvim_buf_set_option(file.buffer, 'modifiable', false)
  end

  vim.cmd [[ windo diffthis ]]
end

M.setup = function(opts)
  M.opts = vim.tbl_deep_extend('force', M.opts, opts)

  vim.api.nvim_create_user_command('SettleInit', M.start, {})
  vim.api.nvim_create_user_command('SettleUse1', M.use_1, {})
  vim.api.nvim_create_user_command('SettleUse2', M.use_2, {})
  vim.api.nvim_create_user_command('SettleClose', M.close, {})

  -- splice compatible mappings
  vim.api.nvim_set_keymap(
    'n',
    M.opts.keymaps.next_conflict,
    '',
    { silent = true, callback = M.next_diff, desc = 'Move to next conflict' }
  )
  vim.api.nvim_set_keymap(
    'n',
    M.opts.keymaps.prev_conflict,
    '',
    { silent = true, callback = M.prev_diff, desc = 'Move to previous conflict' }
  )
  vim.api.nvim_set_keymap(
    'n',
    M.opts.keymaps.use_ours,
    '',
    { silent = true, callback = M.use_1, desc = 'Use changes from 1 (OURS)' }
  )
  vim.api.nvim_set_keymap(
    'n',
    M.opts.keymaps.use_theirs,
    '',
    { silent = true, callback = M.use_2, desc = 'Use changes from 2 (THEIRS)' }
  )
  vim.api.nvim_set_keymap(
    'n',
    M.opts.keymaps.close,
    '',
    { silent = true, callback = M.close, desc = 'Save all changes and close' }
  )
end

return M

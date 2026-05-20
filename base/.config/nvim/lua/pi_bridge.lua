local M = {}

M.config = {
  host = "127.0.0.1",
  port = 47631,
}

local uv = vim.uv or vim.loop
local socket = nil
local connected = false
local read_buffer = ""
local pending = {}
local next_id = 1
local reconnect_timer = nil
local reconnect_delay = 500
local sessions = {}
local selected_target_session_id = nil

local function notify(msg, level)
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, { title = "pi_bridge" })
  end)
end

local function json_encode(tbl)
  return vim.json and vim.json.encode(tbl) or vim.fn.json_encode(tbl)
end

local function json_decode(str)
  return vim.json and vim.json.decode(str) or vim.fn.json_decode(str)
end

local tmux_pane = os.getenv("TMUX_PANE")
local tmux_client_tty = os.getenv("TTY")

local function tmux_display(format)
  local cmd = string.format("tmux display-message -p %q", format)
  local handle = io.popen(cmd)
  if not handle then return nil end
  local out = handle:read("*a")
  local ok = handle:close()
  if not ok then return nil end
  return vim.trim(out or "")
end

local function current_tmux_pane()
  if tmux_pane and tmux_pane ~= "" then return tmux_pane end
  tmux_pane = tmux_display("#{pane_id}")
  return tmux_pane
end

local function current_tmux_client_tty()
  if tmux_client_tty and tmux_client_tty ~= "" then return tmux_client_tty end
  tmux_client_tty = tmux_display("#{client_tty}")
  return tmux_client_tty
end

local function send(tbl)
  if selected_target_session_id and not tbl.targetSessionId then
    tbl.targetSessionId = selected_target_session_id
  end
  if not socket or not connected then
    notify("not connected; retrying pi bridge", vim.log.levels.WARN)
    M.connect()
    return false
  end
  socket:write(json_encode(tbl) .. "\n")
  return true
end

local function current_file()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then return nil end
  return name
end

local function get_visual_selection()
  local mode = vim.fn.mode()
  local s = vim.fn.getpos("'<")
  local e = vim.fn.getpos("'>")
  local start_line, start_col = s[2], s[3]
  local end_line, end_col = e[2], e[3]
  if start_line <= 0 or end_line <= 0 then return nil end
  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then return nil end
  lines[#lines] = string.sub(lines[#lines], 1, end_col)
  lines[1] = string.sub(lines[1], start_col)
  return {
    kind = "selection",
    mode = mode,
    file = current_file(),
    range = { start_line = start_line, start_col = start_col, end_line = end_line, end_col = end_col },
    text = table.concat(lines, "\n"),
  }
end

local function get_buffer_context()
  return {
    kind = "buffer",
    file = current_file(),
    cursor = vim.api.nvim_win_get_cursor(0),
    filetype = vim.bo.filetype,
    text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
  }
end

local function get_diagnostics_context()
  local diags = vim.diagnostic.get(0)
  local out = {}
  for _, d in ipairs(diags) do
    table.insert(out, {
      line = d.lnum + 1,
      column = d.col + 1,
      end_line = d.end_lnum and (d.end_lnum + 1) or nil,
      end_column = d.end_col and (d.end_col + 1) or nil,
      severity = d.severity,
      source = d.source,
      message = d.message,
    })
  end
  return { kind = "diagnostics", file = current_file(), diagnostics = out }
end

local function context_for_kind(kind)
  if kind == "selection" then
    return get_visual_selection() or get_buffer_context()
  elseif kind == "buffer" then
    return get_buffer_context()
  elseif kind == "diagnostics" then
    return get_diagnostics_context()
  else
    return get_visual_selection() or get_buffer_context()
  end
end

local function session_label(session)
  local cwd = session.cwd or "?"
  local name = vim.fn.fnamemodify(cwd, ":t")
  local short = vim.fn.fnamemodify(cwd, ":~")
  local pane = session.tmuxPane and (" · " .. session.tmuxPane) or ""
  local selected = session.sessionId == selected_target_session_id and "● " or "  "
  return string.format("%s%s · %s%s", selected, name, short, pane)
end

local function handle_message(msg)
  if msg.type == "hello" then
    sessions = msg.sessions or sessions
    notify("connected to pi nvim bridge")
  elseif msg.type == "show_message" then
    notify(msg.message or "")
  elseif msg.type == "open_file" then
    vim.schedule(function()
      vim.cmd.edit(vim.fn.fnameescape(msg.file))
      if msg.line then
        vim.api.nvim_win_set_cursor(0, { tonumber(msg.line), tonumber(msg.column or 1) - 1 })
      end
    end)
    send({ replyTo = msg.id, ok = true })
  elseif msg.type == "get_context" then
    local ctx = nil
    vim.schedule(function()
      ctx = context_for_kind(msg.kind)
      send({ replyTo = msg.id, ok = true, context = ctx })
    end)
  elseif msg.type == "sessions" then
    sessions = msg.sessions or {}
  elseif msg.type == "selected_session" then
    selected_target_session_id = msg.targetSessionId
    sessions = msg.sessions or sessions
    notify("selected pi session")
  elseif msg.type == "focused_pi" then
    notify("focused pi pane")
  elseif msg.type == "error" then
    notify(msg.error or "pi bridge error", vim.log.levels.ERROR)
  end
end

local function schedule_reconnect()
  if reconnect_timer then return end
  reconnect_timer = uv.new_timer()
  reconnect_timer:start(reconnect_delay, 0, vim.schedule_wrap(function()
    reconnect_timer:close()
    reconnect_timer = nil
    if not connected then M.connect() end
  end))
  reconnect_delay = math.min(reconnect_delay * 2, 2000)
end

function M.connect()
  if connected then return end
  if socket then pcall(function() socket:close() end) end
  socket = uv.new_tcp()
  socket:connect(M.config.host, M.config.port, function(err)
    if err then
      connected = false
      schedule_reconnect()
      return
    end
    connected = true
    reconnect_delay = 500
    send({
      type = "hello",
      role = "nvim",
      tmuxPane = current_tmux_pane(),
      tmuxClientTty = current_tmux_client_tty(),
    })
    socket:read_start(function(read_err, chunk)
      if read_err then
        notify("read error: " .. tostring(read_err), vim.log.levels.ERROR)
        return
      end
      if not chunk then
        connected = false
        schedule_reconnect()
        return
      end
      read_buffer = read_buffer .. chunk
      while true do
        local idx = read_buffer:find("\n", 1, true)
        if not idx then break end
        local line = read_buffer:sub(1, idx - 1):gsub("\r$", "")
        read_buffer = read_buffer:sub(idx + 1)
        if line ~= "" then
          local ok, msg = pcall(json_decode, line)
          if ok then handle_message(msg) else notify("bad JSON from pi", vim.log.levels.ERROR) end
        end
      end
    end)
  end)
end

function M.disconnect()
  if socket then socket:close() end
  socket = nil
  connected = false
end

function M.send_selection()
  send(vim.tbl_extend("force", { type = "context" }, get_visual_selection() or get_buffer_context()))
end

function M.send_buffer()
  send(vim.tbl_extend("force", { type = "context" }, get_buffer_context()))
end

function M.send_diagnostics()
  send(vim.tbl_extend("force", { type = "context" }, get_diagnostics_context()))
end

function M.list_sessions()
  if not connected then M.connect() end
  vim.defer_fn(function()
    send({ type = "list_sessions" })
  end, connected and 0 or 300)
  vim.defer_fn(function()
    if #sessions == 0 then
      notify("no pi sessions reported yet", vim.log.levels.WARN)
      return
    end
    local lines = {}
    for index, session in ipairs(sessions) do
      table.insert(lines, string.format("%d. %s", index, session_label(session)))
    end
    notify(table.concat(lines, "\n"))
  end, connected and 150 or 600)
end

local function choose_session_with_telescope()
  local ok_pickers, pickers = pcall(require, "telescope.pickers")
  local ok_finders, finders = pcall(require, "telescope.finders")
  local ok_conf, conf = pcall(require, "telescope.config")
  local ok_actions, actions = pcall(require, "telescope.actions")
  local ok_state, action_state = pcall(require, "telescope.actions.state")
  if not (ok_pickers and ok_finders and ok_conf and ok_actions and ok_state) then
    return false
  end

  pickers.new({}, {
    prompt_title = "Pi sessions",
    finder = finders.new_table({
      results = sessions,
      entry_maker = function(session)
        return {
          value = session,
          display = session_label(session),
          ordinal = table.concat({ session.cwd or "", session.tmuxPane or "", session.sessionId or "" }, " "),
        }
      end,
    }),
    sorter = conf.values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not entry then return end
        local choice = entry.value
        selected_target_session_id = choice.sessionId
        send({ type = "select_session", targetSessionId = choice.sessionId })
        notify("selected " .. session_label(choice))
      end)
      return true
    end,
  }):find()
  return true
end

function M.select_session()
  if not connected then M.connect() end
  vim.defer_fn(function()
    send({ type = "list_sessions" })
  end, connected and 0 or 300)
  vim.defer_fn(function()
    if #sessions == 0 then
      notify("no pi sessions reported yet", vim.log.levels.WARN)
      return
    end
    if choose_session_with_telescope() then return end
    vim.ui.select(sessions, {
      prompt = "Select Pi session",
      format_item = session_label,
    }, function(choice)
      if not choice then return end
      selected_target_session_id = choice.sessionId
      send({ type = "select_session", targetSessionId = choice.sessionId })
      notify("selected " .. session_label(choice))
    end)
  end, connected and 150 or 600)
end

function M.clear_selection()
  selected_target_session_id = nil
  notify("pi bridge target reset to auto")
end

function M.focus_pi()
  if not connected then M.connect() end
  vim.defer_fn(function()
    send({ type = "focus_pi" })
  end, connected and 0 or 300)
end

function M.ask(opts)
  opts = opts or {}
  local args = opts.args or ""
  if args == "" then
    vim.ui.input({ prompt = "Pi prompt: " }, function(input)
      if input and input ~= "" then M.ask({ args = input }) end
    end)
    return
  end
  send({ type = "prompt", message = args, context = context_for_kind("selection_or_buffer") })
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  if M.config.auto_connect ~= false then
    vim.defer_fn(function() M.connect() end, 100)
  end
  vim.api.nvim_create_user_command("PiBridgeConnect", function() M.connect() end, {})
  vim.api.nvim_create_user_command("PiBridgeDisconnect", function() M.disconnect() end, {})
  vim.api.nvim_create_user_command("PiSendSelection", function() M.send_selection() end, { range = true })
  vim.api.nvim_create_user_command("PiSendBuffer", function() M.send_buffer() end, {})
  vim.api.nvim_create_user_command("PiSendDiagnostics", function() M.send_diagnostics() end, {})
  vim.api.nvim_create_user_command("PiSessions", function() M.list_sessions() end, {})
  vim.api.nvim_create_user_command("PiSelect", function() M.select_session() end, {})
  vim.api.nvim_create_user_command("PiAuto", function() M.clear_selection() end, {})
  vim.api.nvim_create_user_command("PiFocus", function() M.focus_pi() end, {})
  vim.keymap.set({ "n", "v", "i", "t" }, "<C-\\>", function() M.focus_pi() end, { desc = "Focus selected Pi pane" })
  vim.api.nvim_create_user_command("PiAsk", function(opts2) M.ask(opts2) end, { nargs = "*", range = true })
end

return M

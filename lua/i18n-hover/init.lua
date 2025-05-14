local nio = require("nio")
local process = nio.process

local spinner_frames = { "◐", "◓", "◑", "◒" }
local ns = vim.api.nvim_create_namespace("flatten_locales_spinner")

local current_script_path = debug.getinfo(1, "S").source:sub(2)
local root_path = current_script_path:gsub("/[^/]+/[^/]+/[^/]+$", "")
local script = root_path .. "/scripts/flatten_locales.rb"

local M = {}

function M.get_key_under_cursor()
  local pattern = "t%s*%([\"']([%w_.]+)[\"']%)"
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col(".")
  local init = 1
  while true do
    local s, e, key = line:find(pattern, init)
    if not s then
      break
    end
    if col >= s and col <= e then
      return key
    end
    init = e + 1
  end
  return nil
end

function M.show_hover()
  local key = M.get_key_under_cursor()
  if not key then
    vim.notify("No i18n key found under cursor", vim.log.levels.INFO)
    return
  end
  local lines = { "" }
  for lang, tbl in pairs(M.translations) do
    local val = tbl[key]
    table.insert(lines, string.format("%s: %s", lang, val or "<missing>"))
    table.insert(lines, "")
  end
  vim.lsp.util.open_floating_preview(lines, "plaintext", {
    border = "rounded",
    max_width = 60,
    title = "translations",
  })
end

function M.setup(opts)
  if vim.fn.filereadable(vim.fn.getcwd() .. "/Gemfile") == 0 then
    return
  end
  vim.api.nvim_set_hl(0, "YamlProgressTitle", { link = "Comment" })
  vim.api.nvim_set_hl(0, "YamlProgressSpinner", { link = "Identifier" })

  -- create an unlisted scratch buffer and floating win for spinner
  local buf = vim.api.nvim_create_buf(false, true)
  local win

  -- start the spinner timer
  local running = true
  local idx = 1
  -- spinner timer: update every 100ms
  local timer = vim.loop.new_timer()
  timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if not running then
        timer:stop()
        return
      end

      -- open float on first tick
      if not win or not vim.api.nvim_win_is_valid(win) then
        local prefix = "Parsing Yaml Files for translations: "
        local w = #prefix + 1
        win = vim.api.nvim_open_win(buf, false, {
          relative = "editor",
          anchor = "SE",
          row = vim.o.lines - 2,
          col = vim.o.columns,
          width = w,
          height = 1,
          style = "minimal",
          focusable = false,
          noautocmd = true,
          zindex = 50,
        })
        vim.api.nvim_win_set_option(win, "winblend", 10)
      end

      -- build and write the line
      local prefix = "Parsing Yaml Files for translations: "
      local spin = spinner_frames[idx]
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { prefix .. spin })

      -- clear old highlights…
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      -- …then highlight prefix and spinner
      vim.api.nvim_buf_add_highlight(buf, ns, "YamlProgressTitle", 0, 0, #prefix)
      vim.api.nvim_buf_add_highlight(buf, ns, "YamlProgressSpinner", 0, #prefix, #prefix + 1)

      idx = idx % #spinner_frames + 1
    end)
  )

  opts = vim.tbl_deep_extend("force", {
    keymap = "<leader>ih",
    filetypes = { "lua", "js", "ts", "vue", "html", "rb", "eruby", "slim" },
  }, opts or {})

  nio.run(function()
    local cwd = vim.fn.getcwd()

    local job = process.run({
      cmd = "bundle",
      args = { "exec", "ruby", script, cwd },
    })

    local output = job.stdout.read()
    local exit_code, stderr_lines = job:result(true)

    -- stop the spinner and close the float
    running = false
    -- stop the timer right away
    timer:stop()
    -- close the window on the main loop
    vim.schedule(function()
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end)

    if exit_code ~= 0 then
      vim.schedule(function()
        vim.notify(
          "flatten_locales.rb failed (code="
            .. exit_code
            .. "): "
            .. table.concat(stderr_lines, "\n"),
          vim.log.levels.ERROR
        )
      end)
    end

    local ok, tbl = pcall(vim.json.decode, output)
    if not ok then
      vim.schedule(function()
        vim.notify("i18n load error: " .. tostring(tbl), vim.log.levels.ERROR)
      end)
      return
    end

    M.translations = tbl
  end)

  for _, ft in ipairs(opts.filetypes) do
    vim.api.nvim_create_autocmd("FileType", {
      pattern = ft,
      callback = function()
        vim.keymap.set(
          "n",
          opts.keymap,
          M.show_hover,
          { buffer = true, silent = true, desc = "Show i18n translations under cursor" }
        )
      end,
    })
  end
end

return M

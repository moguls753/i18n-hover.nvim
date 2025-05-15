local nio = require("nio")

local M = {}

M._spinner = {
  buf = nil,
  win = nil,
  timer = nil,
  running = false,
  idx = 1,
}

function M.setup(opts)
  if vim.fn.filereadable(vim.fn.getcwd() .. "/Gemfile") == 0 then
    return
  end

  M.start_progress_spinner()
  M.start_parsing()

  opts = vim.tbl_deep_extend("force", {
    keymap = "<leader>ih",
    filetypes = { "lua", "js", "ts", "vue", "html", "ruby", "eruby", "slim" },
    goto_lang = "en",
    goto_file_keymap = "gf",
  }, opts or {})

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
        vim.keymap.set("n", opts.goto_file_keymap, function()
          M.goto_yaml_file(opts.goto_lang)
        end, {
          noremap = true,
          silent = true,
          desc = "Jump to i18n YAML file",
          buffer = true,
        })
      end,
    })
  end
end

local process = nio.process
local spinner_frames = { "◐", "◓", "◑", "◒" }
local ns = vim.api.nvim_create_namespace("flatten_locales_spinner")
local current_script_path = debug.getinfo(1, "S").source:sub(2)
local root_path = current_script_path:gsub("/[^/]+/[^/]+/[^/]+$", "")
local script = root_path .. "/scripts/flatten_locales.rb"

function M.get_key_under_cursor()
  local pattern = "t%s*%(%s*['\"]([%w_.]+)['\"]"
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
    local val = tbl[key] and tbl[key].translation
    table.insert(lines, string.format("%s: %s", lang, val or "<missing>"))
    table.insert(lines, "")
  end
  vim.lsp.util.open_floating_preview(lines, "plaintext", {
    border = "rounded",
    max_width = 60,
    title = "translations",
  })
end

function M.goto_yaml_file(language)
  local key = M.get_key_under_cursor()
  if not key then
    -- default gf mapping
    vim.cmd("normal! gf")
    return
  end

  if M.translations[language] and M.translations[language][key] then
    local file_path = M.translations[language][key].file
    if file_path and vim.loop.fs_stat(file_path) then
      vim.cmd("edit " .. vim.fn.fnameescape(file_path))
    else
      vim.notify("Translation file not found: " .. (file_path or key), vim.log.levels.ERROR)
    end
  end
  vim.notify("Translation file not found!")
end

function M.start_progress_spinner()
  local s = M._spinner
  s.running = true
  s.idx = 1
  s.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_hl(0, "YamlProgressTitle", { link = "Comment" })
  vim.api.nvim_set_hl(0, "YamlProgressSpinner", { link = "Identifier" })

  s.timer = vim.loop.new_timer()
  s.timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if not s.running then
        s.timer:stop()
        return
      end

      if not s.win or not vim.api.nvim_win_is_valid(s.win) then
        local prefix = "Parsing Yaml Files for translations: "
        local w = #prefix + 1
        s.win = vim.api.nvim_open_win(s.buf, false, {
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
        vim.api.nvim_win_set_option(s.win, "winblend", 10)
      end

      local prefix = "Parsing Yaml Files for translations: "
      local spin = spinner_frames[s.idx]
      vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, { prefix .. spin })
      vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
      vim.api.nvim_buf_add_highlight(s.buf, ns, "YamlProgressTitle", 0, 0, #prefix)
      vim.api.nvim_buf_add_highlight(s.buf, ns, "YamlProgressSpinner", 0, #prefix, #prefix + 1)

      s.idx = s.idx % #spinner_frames + 1
    end)
  )
end

function M.stop_progress_spinner()
  local s = M._spinner
  s.running = false
  if s.timer then
    s.timer:stop()
  end
  vim.schedule(function()
    if s.win and vim.api.nvim_win_is_valid(s.win) then
      vim.api.nvim_win_close(s.win, true)
    end
  end)
end

function M.start_parsing()
  nio.run(function()
    local cwd = vim.fn.getcwd()

    local job = process.run({
      cmd = "ruby",
      args = { script, cwd },
    })

    local output = job.stdout.read()
    local exit_code, stderr_lines = job:result(true)

    M.stop_progress_spinner()

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
end

return M

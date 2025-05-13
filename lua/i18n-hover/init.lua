local nio = require("nio")
local process = nio.process
local fn = vim.fn

-- Detect your plugin root dynamically
local current_script_path = debug.getinfo(1, "S").source:sub(2)
local root_path = current_script_path:gsub("/[^/]+/[^/]+/[^/]+$", "")
local script = root_path .. "/scripts/flatten_locales.rb"

local M = {}

function M.get_key_under_cursor()
  -- pattern for t('foo.bar') or t("foo.bar")
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
  opts = opts or {}

  nio.run(function()
    local cwd = fn.getcwd()

    local job = process.run({
      cmd = "bundle",
      args = { "exec", "ruby", script, cwd },
    })

    local output = job.stdout.read()
    local exit_code, stderr_lines = job:result(true)

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

  local fts = opts.filetypes or { "lua", "js", "ts", "vue", "html", "rb", "eruby", "slim" }
  for _, ft in ipairs(fts) do
    vim.api.nvim_create_autocmd("FileType", {
      pattern = ft,
      callback = function()
        vim.keymap.set("n", "K", M.show_hover, { buffer = true, silent = true })
      end,
    })
  end
end

return M

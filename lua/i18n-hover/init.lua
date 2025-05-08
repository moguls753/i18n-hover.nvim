local M = {}
M.translations = {}

local ok, yaml = pcall(require, "yaml")
if not ok then
  vim.notify("Please `luarocks install lua-yaml` for YAML parsing", vim.log.levels.ERROR)
  return
end

--- Load all YAML translation files from a directory
function M.load_translations(path)
  local files = vim.fn.globpath(path, "*.yml", false, true)
  for _, file in ipairs(files) do
    local basename = file:match("([^/]+)%.yml$")
    local lang = basename and basename:match("([^.]+)$")
    if not lang then
      vim.notify("Could not extract language from filename: " .. file, vim.log.levels.WARN)
    else
      local lines = vim.fn.readfile(file)
      local text = table.concat(lines, "\n")
      local ok, tbl = pcall(yaml.eval, text)
      if ok and type(tbl) == "table" then
        M.translations[lang] = tbl
      else
        vim.notify("Failed to parse translation file: " .. file, vim.log.levels.WARN)
      end
    end
  end
end

local function lookup(tbl, key)
  for part in key:gmatch("([^.]+)") do
    if type(tbl) ~= "table" then
      return nil
    end
    tbl = tbl[part]
    if tbl == nil then
      return nil
    end
  end
  return tbl
end

function M.get_key_under_cursor()
  -- fix: properly escaped pattern for t('foo.bar') or t("foo.bar")
  local pattern = "t%s*%([\"']([%w_.]+)[\"']%)"
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col(".")
  for _, dir in ipairs({ { start = 1, finish = col }, { start = col, finish = #line } }) do
    local snippet = line:sub(dir.start, dir.finish)
    local _, _, key = snippet:find(pattern)
    if key then
      return key
    end
  end
  return nil
end

function M.show_hover()
  local key = M.get_key_under_cursor()
  if not key then
    vim.notify("No i18n key found under cursor", vim.log.levels.INFO)
    return
  end
  local lines = {}
  for lang, tbl in pairs(M.translations) do
    local val = lookup(tbl, key)
    table.insert(lines, string.format("%s: %s", lang, val or "<missing>"))
  end
  vim.lsp.util.open_floating_preview(lines, "plaintext", {
    border = "single",
    max_width = 60,
  })
end

function M.setup(opts)
  opts = opts or {}
  local path = opts.path or (vim.fn.getcwd() .. "/config/locales")
  M.load_translations(path)

  local fts = opts.filetypes or { "lua", "js", "ts", "vue", "html", "rb", "erb", "slim" }
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

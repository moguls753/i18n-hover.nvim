local M = {}
M.translations = {}

local function normalize_rails_yaml(lines)
  -- 1) Quote any Ruby-symbol list items:   - :day  →  - ":day"
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("^(%s*%-)%s*:(%w+)", '%1 "%2"', nil)
  end

  return lines
end

function M.load_translations(path)
  local ok, yaml = pcall(require, "i18n-hover-yaml.yaml")
  if not ok then
    vim.notify("YAML parser failed to load", vim.log.levels.ERROR)
    return
  end

  for _, file in ipairs(vim.fn.globpath(path, "*.yml", false, true)) do
    local lines = vim.fn.readfile(file)
    local text = table.concat(normalize_rails_yaml(lines), "\n")

    local ok, data_or_err = pcall(yaml.eval, text)
    if not ok or type(data_or_err) ~= "table" then
      -- M.translations[file] = tostring(data_or_err)
    else
      for locale, mapping in pairs(data_or_err) do
        local existing = M.translations[locale] or {}
        M.translations[locale] = vim.tbl_deep_extend("force", existing, mapping)
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

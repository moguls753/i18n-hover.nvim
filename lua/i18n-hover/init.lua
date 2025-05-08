local M = {}
M.translations = {}

--- Load all YAML translation files from a directory
--- @param path string: directory containing `*.yml` files
function M.load_translations(path)
  local files = vim.fn.globpath(path, '*.yml', false, true)
  for _, file in ipairs(files) do
    local basename = file:match("([^/]+)%.yml$")
    local lang = basename and basename:match("([^.]+)$")
    if not lang then
      vim.notify("Could not extract language from filename: " .. file, vim.log.levels.WARN)
    else
      local lines = vim.fn.readfile(file)
      local text = table.concat(lines, "\n")
      local ok, tbl = pcall(vim.fn.yaml, text)
      if ok and type(tbl) == 'table' then
        M.translations[lang] = tbl
      else
        vim.notify("Failed to parse translation file: " .. file, vim.log.levels.WARN)
      end
    end
  end
end

--- Lookup a nested key in a table using dot notation
--- @param tbl table: nested table
--- @param key string: dot-separated key path
--- @return any|nil: the value or nil if missing
local function lookup(tbl, key)
  for part in key:gmatch("([^.]+)") do
    if type(tbl) ~= 'table' then return nil end
    tbl = tbl[part]
    if tbl == nil then return nil end
  end
  return tbl
end

--- Extract i18n key under cursor matching t('key.path') or t "key.path"
function M.get_key_under_cursor()
  local pattern = [[t%s*[[(\")]([%w_.]+)[)\"]]]
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col('.')
  for _, dir in ipairs({{start=1, finish=col}, {start=col, finish=#line}}) do
    local snippet = line:sub(dir.start, dir.finish)
    local _, _, key = snippet:find(pattern)
    if key then return key end
  end
  return nil
end

--- Show a floating window with all translations for the key under cursor
function M.show_hover()
  local key = M.get_key_under_cursor()
  if not key then
    vim.notify('No i18n key found under cursor', vim.log.levels.INFO)
    return
  end
  local lines = {}
  for lang, tbl in pairs(M.translations) do
    local val = lookup(tbl, key)
    table.insert(lines, string.format('%s: %s', lang, val or '<missing>'))
  end
  vim.lsp.util.open_floating_preview(lines, 'plaintext', { border = 'single', max_width = 60 })
end

--- Setup plugin: load translations and map K
--- @param opts table
---   - path string: where to find `.yml` files
---   - filetypes table: list of filetypes to enable hover
function M.setup(opts)
  opts = opts or {}
  local path = opts.path or (vim.fn.stdpath('config') .. '/locales')
  M.load_translations(path)
  local fts = opts.filetypes or { 'lua', 'js', 'ts', 'vue', 'html', 'rb', 'erb' }
  for _, ft in ipairs(fts) do
    vim.api.nvim_create_autocmd('FileType', {
      pattern = ft,
      callback = function()
        vim.keymap.set('n', 'K', M.show_hover, { buffer = true, silent = true })
      end,
    })
  end
end

return M

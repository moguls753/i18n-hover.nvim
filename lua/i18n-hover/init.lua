local M = {}
M.translations = {}

function M.load_translations(path)
  for _, file in ipairs(vim.fn.globpath(path, "*.yml", false, true)) do
    local lines = vim.fn.readfile(file)

    local indents_seen = {}
    for _, line in ipairs(lines) do
      local indent = line:match("^(%s*).-:%s*")
      if indent and #indent > 0 then
        indents_seen[#indent] = true
      end
    end

    local sizes = {}
    for n in pairs(indents_seen) do
      table.insert(sizes, n)
    end
    table.sort(sizes)
    local indent_size = sizes[1] or 2

    local result, key_path = {}, {}
    for _, line in ipairs(lines) do
      local indent, key, value = line:match("^(%s*)(.-)%s*:%s*(.*)$")
      if key and key ~= "" then
        local level = math.floor(#indent / indent_size)
        key_path[level + 1] = key
        for i = level + 2, #key_path do
          key_path[i] = nil
        end
        result[table.concat(key_path, ".")] = value
      end
    end
  end
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

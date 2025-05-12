local M = {}
M.translations = {}

local function detect_indentation_width(lines)
  local indents_seen = {}
  local sizes = {}
  for _, line in ipairs(lines) do
    local indent = line:match("^(%s*).-:%s*")
    if indent and #indent > 0 then
      indents_seen[#indent] = true
    end
  end
  for n in pairs(indents_seen) do
    table.insert(sizes, n)
  end
  table.sort(sizes)
  return sizes[1] or 2
end

local function detect_language(lines)
  for _, line in ipairs(lines) do
    local indent, key = line:match("^(%s*)([%w_%-]+)%s*:%s*")
    if indent and #indent == 0 and key then
      return key
    end
  end
end

local function flatten_lines(lines, language, indent_size)
  local key_path = {}
  local flattened_lines = {}
  for _, line in ipairs(lines) do
    local indent, key, value_space, value = line:match("^(%s*)([^%s:]+):(%s*)(.*)$")
    if key and key ~= "" then
      local level = math.floor(#indent / indent_size)
      key_path[level + 1] = key
      for i = level + 2, #key_path do
        key_path[i] = nil
      end

      if #value_space > 0 and value and value ~= "" then
        local full = table.concat(key_path, ".")
        local subkey = full:match("^" .. language .. "%.(.+)$")
        if subkey then
          flattened_lines[subkey] = value
        end
      end
    end
  end
  return flattened_lines
end

function M.load_translations()
  local files = vim.api.nvim_get_runtime_file("config/locales/*.yml", true)
  for _, file in ipairs(files) do
    local lines = vim.fn.readfile(file)
    local indent_size = detect_indentation_width(lines)
    local language = detect_language(lines)

    M.translations[language] = M.translations[language] or {}

    local flat_lines = flatten_lines(lines, language, indent_size)

    for key, value in pairs(flat_lines) do
      M.translations[language][key] = value
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
  M.load_translations()

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

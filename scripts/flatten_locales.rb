#!/usr/bin/env ruby
require 'yaml'
require 'json'
require 'pathname'

# Recursively flatten a nested hash of translations.
# - obj: the current nested hash (or value) to flatten
# - prefix: the key prefix (dot-separated) accumulated so far
# - result_hash: the hash to populate with flattened keys
# - source_file: the source file path for the current translations
def flatten_keys(obj, prefix, result_hash, source_file)
  obj.each do |k, v|
    full_key = prefix.empty? ? k.to_s : "#{prefix}.#{k}"
    if v.is_a?(Hash)
      flatten_keys(v, full_key, result_hash, source_file)
    else
      result_hash[full_key] = {
        translation: v.to_s,
        file:        source_file
      }
    end
  end
end

# 1) Fetch & absolute-ize the project root
base = ARGV.fetch(0) { abort "usage: flatten.rb /path/to/project" }
base_dir = Pathname.new(base).expand_path

# Will hold: { "en" => { "foo.bar" => { translation: "...", file: "config/locales/en.yml" }, … }, … }
flattened = {}

# 2) Glob *absolute* paths under base_dir
Dir.glob(base_dir.join("config", "locales", "**", "*.yml")).each do |file_path|
  file_path = Pathname.new(file_path)        # now absolute
  data      = YAML.load_file(file_path)

  # 3) A shorter, project-relative path for notifications/jumping
  rel_file  = file_path.relative_path_from(base_dir).to_s

  data.each do |lang, subtree|
    flattened[lang] ||= {}
    flatten_keys(subtree, "", flattened[lang], rel_file)
  end
end

# Output the flattened structure as JSON
puts JSON.pretty_generate(flattened)
#
# #!/usr/bin/env ruby
#
# require 'yaml'
# require 'json'
#
# base = ARGV.fetch(0) { abort "usage: flatten_locales.rb /path/to/project" }
#
# translations = {}
#
# def flatten_hash(h, prefix = nil)
#   h.flat_map do |k, v|
#     full_key = prefix ? "#{prefix}.#{k}" : k.to_s
#     if v.is_a?(Hash)
#       flatten_hash(v, full_key).to_a
#     else
#       [[full_key, v.to_s]]
#     end
#   end.to_h
# end
#
# pattern = File.join(base, "**", "config", "locales", "*.yml")
# Dir.glob(pattern).each do |path|
#   data = YAML.load_file(path)
#   data.each do |lang, subtree|
#     translations[lang] ||= {}
#     translations[lang].merge!(flatten_hash(subtree))
#   end
# end
#
# puts translations.to_json

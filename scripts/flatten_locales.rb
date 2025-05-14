#!/usr/bin/env ruby

# This script provides a hash like:
# {
#   "de": {
#     "hello": { 
#       "translation": "Hallo",
#       "file": config/locales/de.yml,
#     }
#   }
#   "en": {
#     "hello": {
#       "translation": "Hello",
#       "file": config/locales/eb.yml,
#     }
#   }
# }

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

base = ARGV.fetch(0) { abort "usage: flatten_locales.rb /path/to/project" }

translations = {}

pattern = File.join(base, "**", "config", "locales", "*.yml")
Dir.glob(pattern).each do |file_path|
  file_path = Pathname.new(file_path)
  data      = YAML.load_file(file_path)

  rel_file  = file_path.relative_path_from(base).to_s

  data.each do |lang, subtree|
    translations[lang] ||= {}
    flatten_keys(subtree, "", translations[lang], rel_file)
  end
end

puts JSON.pretty_generate(translations)

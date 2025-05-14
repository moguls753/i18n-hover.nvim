#!/usr/bin/env ruby

require 'yaml'
require 'json'

base = ARGV.fetch(0) { abort "usage: flatten_locales.rb /path/to/project" }

translations = {}

def flatten_hash(h, prefix = nil)
  h.flat_map do |k, v|
    full_key = prefix ? "#{prefix}.#{k}" : k.to_s
    if v.is_a?(Hash)
      flatten_hash(v, full_key).to_a
    else
      [[full_key, v.to_s]]
    end
  end.to_h
end

pattern = File.join(base, "**", "config", "locales", "*.yml")
Dir.glob(pattern).each do |path|
  data = YAML.load_file(path)
  data.each do |lang, subtree|
    translations[lang] ||= {}
    translations[lang].merge!(flatten_hash(subtree))
  end
end

puts translations.to_json

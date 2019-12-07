require 'kramdown'
require 'yaml'
require 'ostruct'

START_CHAPTERS = [
  {title: 'Introduction', path: '/'}
]
FINAL_CHAPTERS = [
  {title: 'History (of this site)', path: '/History.html'},
  {title: 'Contributing', path: '/Contributing.html'}
]

class Hash
  def deep_stringify_keys
    _stringify_keys_any(self)
  end

  def _stringify_keys_any(v)
    case v
    when Hash
      v.map { |k, v| [k.to_s, _stringify_keys_any(v)] }.to_h
    when Array
      v.map(&method(:_stringify_keys_any))
    else
      v
    end
  end
end

chapters = START_CHAPTERS.dup

HTML = Kramdown::Converter::Html

def nest_headers(headers, level = 1)
  res = []
  while !headers.empty? && headers.first.level == level
    cur = headers.shift
    children = nest_headers(headers, level + 1)
    cur.children = children
    res << cur
  end
  res
end

# It is Kramdown::Base#basic_generate_id
def id(str)
  gen_id = str.gsub(/^[^a-zA-Z]+/, '')
  gen_id.tr!('^_a-zA-Z0-9 -', '')
  gen_id.tr!(' ', '-')
  gen_id.downcase!
  gen_id
end

def toc_entries(nodes, prefix, **extra)
  nodes.map do |node|
    {
      title: node.html,
      path: node.level == 1 ? prefix : "#{prefix}##{id(node.text)}",
      **(node.level == 1 ? extra : {}),
      children: toc_entries(node.children, prefix)
    }.tap { |h| h.delete(:children) if h[:children].empty? }
  end
end

def inner_html(h)
  h.options[:encoding] = 'UTF-8'
  h.type = :root
  HTML.convert(h).first
end

Dir['_src/*.md'].grep(/\d/).sort.reverse.each do |path|
  ver = path.scan(%r{_src/(.+)\.md}).flatten.first

  text = File.read(path)
  doc = Kramdown::Document.new(text)

  headers = doc.root.children
    .select { |c| c.type == :header }
    .map { |c|
      OpenStruct.new(level: c.options[:level], text: c.options[:raw_text], html: inner_html(c))
    }

  nesting = nest_headers(headers)
  pub = text[/\*\*This document first published:\*\* (.+)\n/, 1] or fail "Published at not found"
  desc = text[/\#\# Highlights\n(.+?)\n\#\# /m, 1] or fail "Description not found"
  desc = desc
    .gsub(/\[(.+?)\]\(.+?\)/, '\1') # remove links
    .then { |highlights| "**Highlights:**\n\n" + highlights + "\n\n[Read more »](https://rubyreferences.github.io/rubychanges/#{ver}.html)" }
    .then(&Kramdown::Document.method(:new))
    .to_html

  chapters.concat(toc_entries(nesting, "/#{ver}.html", is_version: true, published_at: pub, description: desc))
end

chapters.concat(FINAL_CHAPTERS)

File.write('_data/book.yml', {chapters: chapters}.deep_stringify_keys.to_yaml)
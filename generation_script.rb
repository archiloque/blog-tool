#!/usr/bin/env ruby

[
  'BLOG_ROOT_PATH',
  'BLOG_TARGET_PATH',
  'BLOG_ROOT_URL',
  'BLOG_NAME',
].each do |key|
  unless ENV[key]
    raise "Env key [#{key}] is not defined"
  end
end

BLOG_SOURCE_PATH = ENV['BLOG_ROOT_PATH']
BLOG_TARGET_PATH = ENV['BLOG_TARGET_PATH']
BLOG_ROOT_URL = ENV['BLOG_ROOT_URL']
BLOG_NAME = ENV['BLOG_NAME']
DISPLAY_ARTICLE_INFO = (ENV['DISPLAY_ARTICLE_INFO'] != 'no')

LOGO_FILE = 'logo.png'

BLOG_ARTICLE_BASE_NAME = 'README.asciidoc'
BLOG_ARTICLE_TARGET_NAME = 'index.html'
SITEMAP_FILE = 'sitemap.xml'
ATOM_FILE = 'atom.xml'

require 'asciidoctor'
require 'erb'
require 'tilt'
require 'json'
require 'rss'
require 'nokogiri'
require 'pygments'
require 'asciidoctor/converter/html5'
require 'fastimage'
require 'fileutils'

class Asciidoctor::Converter::Html5Converter

  def preamble(node)
    toc = if (node.attr? 'toc') && (node.attr? 'toc-placement', 'preamble')
            %(\n<div id="toc" class="#{node.attr 'toc-class', 'toc'}">
<div id="toctitle">#{node.attr 'toc-title'}</div>
#{outline node.document}
</div>)
          end
    %(#{toc}#{node.content})
  end

end

unless BLOG_ROOT_URL.end_with? '/'
    raise "BLOG_ROOT_URL should end with a '/'"
end

SITE_LOGO_URL = "#{BLOG_ROOT_URL}#{LOGO_FILE}"
SITE_LOGO_SIZE = FastImage.size("static/#{LOGO_FILE}", :raise_on_failure => true)

unless Dir.exist? BLOG_TARGET_PATH
  FileUtils.mkpath BLOG_TARGET_PATH
end

class Author

  attr_reader :name, :twitter_handle, :fb_url, :main_url

  def initialize(name, author)
    @twitter_handle = author['twitter_handle']
    @fb_url = author['fb_url']
    @main_url = author['main_url']
    @name = name
  end
end

AUTHORS = {}
JSON.parse(File.read('authors.json')).collect do |name, value|
  author = Author.new(name, value)
  if value['default_author']
    DEFAULT_AUTHOR = author
  end
  AUTHORS[name] = author
end

def authors_details_from_names(authors)
  authors.split(',').map do |a|
    a.strip!
    if AUTHORS.key? a
      AUTHORS[a]
    else
      raise "Unknown author [#{a}]"
    end
  end
end

ARTICLES = []

class Article

  FRENCH_MONTHS = [nil, 'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre']

  attr_reader :dir_name, :document, :source_dir, :date, :last_modified_time

  def initialize(root_url, dir_name, document, source_dir, last_modified_time)
    @root_url = root_url
    @dir_name = dir_name
    @document = document
    @source_dir = source_dir
    @date = Date.parse(document.revdate)
    @last_modified_time = last_modified_time
    @raw_content = document.render
    @parsed_content = Nokogiri::HTML::fragment(@raw_content)
    improve_images
    create_feed_content
  end

  def improve_images
    @parsed_content.css('img').each do |img|
      img_size = fetch_image_size(img['src'])
      img['width'] = "#{img_size[0]}px"
      img['height'] = "#{img_size[1]}px"
    end
  end

  def create_feed_content
    @feed_content = @parsed_content.dup
    @feed_content.css('img').each do |img|
      img['src'] = "#{absolute_url}#{img['src']}"
    end
  end

  def title
    document.doctitle
  end

  def description
    document.attributes['article_description']
  end

  def authors
    document.attributes['authors']
  end

  def image
    document.attributes['article_image']
  end

  def image_size
    if image
      fetch_image_size(image)
    else
      nil
    end
  end

  def lang
    document.attributes['article_lang'] || 'fr'
  end

  def absolute_url
    @root_url + dir_name + '/'
  end

  def content
    @parsed_content.to_s
  end

  def feed_content
    @feed_content.to_s
  end

  def ignore_files
    (document.attributes['ignore_files'] || '').split(',').collect { |i| i.strip }
  end

  def formatted_date
    if lang == 'fr'
      "le #{date.day} #{FRENCH_MONTHS[date.month]} #{date.year}"
    else
      date.strftime '%B %e, %Y'
    end
  end

  private

  def fetch_image_size(image_path)
    image_full_path = File.join(source_dir, image_path)
    FastImage.size(image_full_path, :raise_on_failure => true)
  end

end

[
  BLOG_TARGET_PATH,
  BLOG_SOURCE_PATH,
  ].each do |dir|
  unless Dir.exist? dir
    raise "[#{dir}] does not exist"
  end
  unless File.directory? dir
    raise "[#{dir}] is not a directory"
  end
end

Dir.glob(File.join(BLOG_SOURCE_PATH, '*')).each do |article_dir|
  if File.directory? article_dir
    article_file = File.join(article_dir, BLOG_ARTICLE_BASE_NAME)
    unless File.exist? article_file
      raise "[#{article_file}] does not exist"
    end
    p "Processing [#{article_file}]"
    article_document = Asciidoctor.load(
      File.readlines(article_file),
      {
        :base_dir => article_dir,
        :safe => Asciidoctor::SafeMode::UNSAFE,
        :attributes => {
          'source-highlighter' => 'pygments'
        }
      })
    ARTICLES << Article.new(
      BLOG_ROOT_URL,
      File.basename(article_dir),
      article_document,
      article_dir,
      File.mtime(article_file)
    )
  end
end

ARTICLES.sort_by! { |article| article.date }.reverse!

# Render main page
main_template = Tilt::ERBTemplate.new('templates/main.erb.html', :default_encoding => 'UTF-8')
main_target_file = File.join(BLOG_TARGET_PATH, BLOG_ARTICLE_TARGET_NAME)
p "Rendering main [#{main_target_file}]"
File.open(main_target_file, 'w') do |file|
  file.puts(
    main_template.render(
      Object.new,
      {
        :articles => ARTICLES,
        :blog_root_url => BLOG_ROOT_URL,
        :author => DEFAULT_AUTHOR,
        :site_logo_url => SITE_LOGO_URL,
        :site_logo_size => SITE_LOGO_SIZE,
        :blog_name => BLOG_NAME,
        :display_article_info => DISPLAY_ARTICLE_INFO,
      }))
end

# Render atom
atom_target_file = File.join(BLOG_TARGET_PATH, ATOM_FILE)
p "Rendering atom [#{atom_target_file}]"
rss = RSS::Maker.make('atom') do |maker|
  channel = maker.channel

  channel.id = "#{BLOG_ROOT_URL}"
  channel.author = DEFAULT_AUTHOR.name
  channel.updated = Time.now.xmlschema
  channel.links.new_link do |link|
    link.href = BLOG_ROOT_URL
  end
  channel.links.new_link do |link|
    link.href= "#{BLOG_ROOT_URL}atom.xml"
    link.rel = 'self'
  end
  channel.title = BLOG_NAME
  channel.description = BLOG_NAME
  channel.language = 'fr'

  ARTICLES.each do |article|
    article_authors = authors_details_from_names(article.authors)

    maker.items.new_item do |item|
      item.link = "#{BLOG_ROOT_URL}#{article.dir_name}/"
      item.updated = article.last_modified_time.xmlschema
      item.published = article.date.xmlschema

      item.title = article.title
      article_authors.each do |article_author|
        item.authors.new_author do |author|
          author.name = article_author.name
          author.uri = article_author.main_url
        end
      end
      item.summary = article.description

      item.content.type = 'html'
      item.content.content = article.feed_content
    end
  end
end

File.open(atom_target_file, 'w') do |file|
  file.puts(rss)
end

# Render sitemap
sitemap_target_file = File.join(BLOG_TARGET_PATH, SITEMAP_FILE)
p "Rendering sitemap [#{sitemap_target_file}]"
sitemap_builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
  xml.urlset(xmlns: 'http://www.sitemaps.org/schemas/sitemap/0.9') do
    xml.url do
      xml.loc "#{BLOG_ROOT_URL}"
    end

    ARTICLES.each do |article|
      xml.url do
        xml.loc "#{BLOG_ROOT_URL}#{article.dir_name}/"
      end
    end
  end
end

File.open(sitemap_target_file, 'w') do |file|
  file.puts(sitemap_builder.to_xml)
end

##
# Copy a file if the timestamp is different
# @param source {String}
# @param target {String}
def copy_if_different(source, target)
  unless File.exist?(target) && (File.mtime(source) == File.mtime(target))
    p "Copy [#{source}] to [#{target}]"
    FileUtils.copy_entry source, target, true
  end
end

article_template = Tilt::ERBTemplate.new('templates/article.erb.html', :default_encoding => 'UTF-8')

##
# Render a content
# @param target_file {String} the target file
# @param template {Tilt::ERBTemplate} the template to use
# @param parameters {Hash} parameters for the templates
def render_content(target_file, template, parameters)
  p "Rendering [#{target_file}]"
  File.open(target_file, 'w') do |file|
    file.puts(
      template.render(Object.new, parameters))
  end
end

ARTICLES.each_with_index do |article, article_index|
  article_authors = authors_details_from_names(article.authors)
  article_parameters = {
    :article => article,
    :blog_root_url => BLOG_ROOT_URL,
    :authors => article_authors,
    :article_date => article.formatted_date,
    :article_published => article.date,
    :article_updated => article.last_modified_time,
    :lang => article.lang,
    :site_logo_url => SITE_LOGO_URL,
    :site_logo_size => SITE_LOGO_SIZE,
    :default_author => DEFAULT_AUTHOR,
    :next_article => (article_index != 0) ? ARTICLES[article_index - 1] : nil,
    :previous_article => (article_index != (ARTICLES.length() -1)) ? ARTICLES[article_index + 1] : nil,
    :blog_name => BLOG_NAME,
    :display_article_info => DISPLAY_ARTICLE_INFO,
  }

  article_target_dir = File.join(BLOG_TARGET_PATH, article.dir_name)

  # Create parent dir
  unless File.exist? article_target_dir
    Dir.mkdir article_target_dir
  end

  # Render article
  article_target_file = File.join(article_target_dir, BLOG_ARTICLE_TARGET_NAME)
  render_content(
    article_target_file,
    article_template,
    article_parameters.merge({:article_content => article.content}))

  # Copy other files
  existing_files = Dir.glob(File.join(article_target_dir, '*')).collect { |f| File.basename(f) }
  existing_files -= [BLOG_ARTICLE_TARGET_NAME]
  ignore_files = article.ignore_files + [BLOG_ARTICLE_BASE_NAME, 'README.html']
  Dir.glob(File.join(article.source_dir, '*')).each do |attached_file_source|
    attached_file_base_name = File.basename(attached_file_source)
    unless ignore_files.include? attached_file_base_name
      attached_file_target = File.join(article_target_dir, attached_file_base_name)
      copy_if_different(attached_file_source, attached_file_target)
      existing_files -= [attached_file_base_name]
    end
  end

  # Delete unused files
  existing_files.each do |file_to_delete|
    file_to_delete_with_path = File.join(article_target_dir, file_to_delete)
    p "Deleting [#{file_to_delete_with_path}]"
    File.delete file_to_delete_with_path
  end

end

BLOG_CSS_FILE = 'blog.css'

p 'Static files'
Dir.glob(File.join('static', '*')).each do |file|
  file_basename = File.basename(file)
  unless [BLOG_CSS_FILE].include? file_basename
    copy_if_different(file, File.join(BLOG_TARGET_PATH, file_basename))
  end
end

p 'Blog.css'
blog_css_content = IO.read(File.join('static', BLOG_CSS_FILE))
pygment_stylesheet_content = Asciidoctor::Stylesheets.instance.pygments_stylesheet_data('fruity')
File.open(File.join(BLOG_TARGET_PATH, BLOG_CSS_FILE), 'w') do |file|
  file << "#{blog_css_content}\n/* Pygments */\n#{pygment_stylesheet_content}"
end

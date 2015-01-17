BLOG_SOURCE_PATH = ENV['BLOG_ROOT_PATH'] || '../blog/publies'
BLOG_TARGET_PATH = ENV['BLOG_TARGET_PATH'] || '../blog-generated'
BLOG_ROOT_URL = ENV['BLOG_ROOT_URL'] || 'http://archiloque.net/blog/'

BLOG_ARTICLE_BASE_NAME = 'README.asciidoc'

require 'asciidoctor'
require 'erb'
require 'tilt'
require 'json'
unless BLOG_ROOT_URL.end_with? '/'
  raise "BLOG_ROOT_URL should end with a '/'"
end

unless Dir.exist? BLOG_TARGET_PATH
  Dir.mkdir BLOG_TARGET_PATH
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

ARTICLES = []

class Article

  MONTHS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre']

  attr_reader :dir_name, :document, :source_dir, :date

  def initialize(dir_name, document, source_dir)
    @dir_name = dir_name
    @document = document
    @source_dir =source_dir
    @date = Date.parse(document.revdate)
  end

  def title
    document.doctitle
  end

  def description
    document.attributes['article_description']
  end

  def author
    document.author
  end

  def image
    document.attributes['article_image']
  end

  def content
    document.render
  end

  def ignore_files
    (document.attributes['ignore_files'] || '').split(',').collect{|i| i.strip}
  end

  def formatted_date
    "#{date.day} #{MONTHS[date.month]} #{date.year}"
  end

end

[BLOG_TARGET_PATH, BLOG_SOURCE_PATH].each do |dir|
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
    article_document = Asciidoctor.load(File.readlines(article_file))
    ARTICLES << Article.new(
        File.basename(article_dir),
        article_document,
        article_dir
    )
  end
end

def copy_if_different(source, target)
  unless File.exist?(target) && (File.mtime(source) == File.mtime(target))
    p "Copy [#{source}] to [#{target}]"
    FileUtils.copy_entry source, target, true
  end
end

# Render main page
main_template = Tilt::ERBTemplate.new('templates/main.erb.html', :default_encoding => 'UTF-8')
main_target_file = File.join(BLOG_TARGET_PATH, 'index.html')
p "Rendering [#{main_target_file}]"
File.open(main_target_file, 'w') do |file|
  file.puts(
      main_template.render(
          Object.new,
          {
              :articles => ARTICLES.sort_by!{|article| article.date}.reverse,
              :blog_root_url => BLOG_ROOT_URL,
              :author => DEFAULT_AUTHOR
          }))
end


article_template = Tilt::ERBTemplate.new('templates/article.erb.html', :default_encoding => 'UTF-8')

ARTICLES.each do |article|
  article_target_dir = File.join(BLOG_TARGET_PATH, File.basename(article.dir_name))

  unless File.exist? article_target_dir
    File.mkdir article_target_dir
  end

  # Render article
  target_file = File.join(article_target_dir, 'index.html')
  p "Rendering [#{target_file}]"
  article_author = AUTHORS[article.author]
  File.open(target_file, 'w') do |file|
    file.puts(
        article_template.render(
            Object.new,
            {
                :blog_root_url => BLOG_ROOT_URL,
                :article_root_url => BLOG_ROOT_URL + article.dir_name + '/',
                :article_content => article.content,
                :article_title => article.title,
                :author => article_author,
                :article_date => article.formatted_date,
                :article_description => article.description,
                :article_image => article.image
            }))
  end

  # Copy other files
  existing_files = Dir.glob(File.join(article_target_dir, '*')).collect { |f| File.basename(f) }
  existing_files -= ['index.html']
  ignore_files = article.ignore_files + [BLOG_ARTICLE_BASE_NAME]
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

p 'Static files'
Dir.glob(File.join('static', '*')).each do |file|
  copy_if_different(file, File.join(BLOG_TARGET_PATH, File.basename(file)))
end

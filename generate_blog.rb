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

ARTICLES = []
AUTHORS = JSON.parse(File.read('authors.json'))
class Article

  attr_reader :dir_name, :document, :source_dir

  def initialize(dir_name, document, source_dir)
    @dir_name = dir_name
    @document = document
    @source_dir =source_dir
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

  def date
    document.revdate
  end

  def image
    document.attributes['article_image']
  end

  def content
    document.render
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

main_template = Tilt::ERBTemplate.new('templates/main.erb.html', :default_encoding => 'UTF-8')
# Render article
main_target_file = File.join(BLOG_TARGET_PATH, 'index.html')
p "Rendering [#{main_target_file}]"
File.open(main_target_file, 'w') do |file|
  file.puts(
      main_template.render(
          Object.new,
          {
              :articles => ARTICLES,
              :blog_root_url => BLOG_ROOT_URL,
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
  File.open(target_file, 'w') do |file|
    file.puts(
        article_template.render(
            Object.new,
            {
                :blog_root_url => BLOG_ROOT_URL,
                :article_root_url => BLOG_ROOT_URL + article.dir_name,
                :article_content => article.content,
                :article_title => article.title,
                :article_author => article.author,
                :author_url => AUTHORS[article.author]['main_url'],
                :author_fb_url => AUTHORS[article.author]['fb_url'],
                :article_date => article.date,
                :article_description => article.description,
                :article_image => article.image
            }))
  end

  # Copy other files
  existing_files = Dir.glob(File.join(article_target_dir, '*')).collect { |f| File.basename(f) }
  existing_files -= ['index.html']
  Dir.glob(File.join(article.source_dir, '*')).each do |attached_file_source|
    attached_file_base_name = File.basename(attached_file_source)
    unless attached_file_base_name == BLOG_ARTICLE_BASE_NAME
      attached_file_target = File.join(article_target_dir, attached_file_base_name)
      copy_if_different(attached_file_source, attached_file_target)
      existing_files -= [attached_file_base_name]
    end
  end

  # Delete unused file
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

require 'fileutils'
require 'optparse'
require 'ostruct'

def log(msg)
  puts msg
end

def extract(regex, str)
  m = regex.match str
  if m.nil?
    return nil
  end
  m[1]
end

class Translate
  attr_accessor :src, :dest

  def initialize(src, dest = nil, filter = nil, force = false)
    @src = src
    @dest = dest
    @filter = filter ? Regexp.new(filter) : nil
    @force = force
    if dest.nil?
      @dest = 'out'
    end

    def filter(path)
      return true if @filter.nil?
      return true if (@filter =~ path) != nil
      false
    end

    def start
      Dir.glob("#{@src}/**/*.{md,html,txt,markdown}")
          .select {|f| File.file? f}
          .select {|f| self.filter f }
          .each do |src|
        log "==== Processing started === (#{src})"
        subtree = File.dirname(src)
        dest_dir = File.join(@dest, subtree[@src.length, subtree.length])
        dest_file_name = File.basename(src, ".*") + '.html'
        dest = File.join(dest_dir, dest_file_name)

        log "Output file: #{dest}"

        if !@force && File.exists?(dest)
          if File.mtime(dest) > File.mtime(src)
            log "<<< Source file was not updated -> skip >>>"
            next
          end
        end

        FileUtils.mkdir_p dest_dir
        processor = FileProcessor.new(src)
        File.open(dest, mode: 'w:UTF-8') do |f|
          f.write(processor.output)
        end
        log "**** Processing finished **** (#{src})"
      end
    end
  end
end

class FileProcessor
  attr_accessor :lines_converter

  def initialize(source)
    @src = source
    @output = nil
    @lines = []
    @reader = nil
    @episode = nil
    unless File.exists? source
      raise "File not found: #{source}"
    end
    unless File.readable? source
      raise "File is not readable: #{source}"
    end
  end

  def output
    if @output.nil?
      process
    end
    @output
  end

  def process
    begin
      @reader = File.open(@src, 'r:UTF-8')
      read_front_matter
      readScript
      @output = @lines.join
    rescue EOFError
      @output = @lines.join
    ensure
      @reader.close unless @reader.nil?
    end
  end

  private

  def read_front_matter
    write skip_until_next {|line| (/^---/ =~ line) != nil}
    line = copy_until_next {|line| (/^episode/ =~ line) != nil}
    @episode = extract(/(\d+)/, line)
    write line
    write copy_until_next {|line| (/^---/ =~ line) != nil}
  end

  def readScript
    if @lines_converter.nil?
      @lines_converter = LineConverter.new
      @lines_converter.images_path = File.join('images', "ep#{@episode}")
    end
    direct_copy_mode = false
    zone_mode = 0
    while true do
      line = @reader.readline.strip
      if line.empty?
        writel '<div class="delimeter" />' and next
      end
      if /^<>/ =~ line
        direct_copy_mode = !direct_copy_mode
        next
      end
      if direct_copy_mode
        writel line
        next
      end
      if /^--\s*\(/ =~ line
        zone_mode = zone_mode + 1
        writel '<div class="zone">' + '<div class="header">' + wrap_content(lines_converter.zone(line)) + '</div>'
        next
      end
      if /^--\s*$/ =~ line
        zone_mode = zone_mode - 1
        writel '</div>'
        next
      end
      if /^--\s*[^\(]+/u =~ line
        writel "\n<div class=\"event\">#{wrap_content(@lines_converter.event(line))}</div>\n" and next
      end
      if /^\[.+\]/ =~ line
        writel "\n<div class=\"notice\">#{wrap_content(@lines_converter.notice(line))}</div>\n" and next
      end
      if /^!(.+)!$/ =~ line
        writel "\n<div class=\"image\">#{@lines_converter.image(line)}</div>\n" and next
      end
      writel "<div class=\"serif\">#{@lines_converter.serif(line)}</div>" and next
    end
    if zone_mode > 0
      log "!!! ----- Unclosed zone specifier detected!!! ---- !!!"
    end
  end

  def skip_until_next
    while true do
      line = @reader.readline
      if yield line
        return line
      end
    end
  end

  def copy_until_next
    while true do
      line = @reader.readline
      if yield line
        return line
      end
      write line
    end
  end

  def write(str)
    @lines.push str
  end

  def writel(src)
    write(src + $/)
  end

  def wrap_content(wrapped)
    '<span class="content">' + wrapped + '</span>'
  end
end

class LineConverter
  attr_accessor :images_path

  def serif(str)
    m = /^([^:]*):(.+)$/.match str
    if m.nil?
      return process_inline str
    end

    content = process_inline m[2]

    "<div class=\"name\">#{m[1]}</div><div class=\"content\">#{content}</div>"
  end

  def event(str)
    extract(/^--(.+)/, str).strip
  end

  def notice(str)
    extract(/^\[(.+)\]/, str).strip
  end

  def image(str)
    image_name = extract(/!(.+)!/, str).strip
    unless /\.[[:alpha:]]+$/ =~ image_name
      image_name = "#{image_name}.png"
    end
    image_name = '{{site.baseurl}}{{page.resources_path}}{{page.resources_story_path}}/' +  image_name
    "<img src=\"#{image_name}\" />"
  end

  def zone(str)
    extract(/\((.*)\)/, str)
  end

  private

  def process_inline(line)
    line
    .gsub(/\//, '<br/>')
    .gsub(/\*(.+?)\*/, '<em>*\1*</em>')
    .gsub(/\((.+?)\)/, '<span class="minds">(\1)</span>')
  end
end

options = OpenStruct.new
options.src = nil
options.out = "out"
options.filter = nil
options.force = false
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: script_translate -s <sources root> -d <output root> -f <filter> -u'
  opts.on("-s", "--source DIR", "Root directory for source scanning") do |source|
    options.src = source
  end
  opts.on("-d", "--destination DIR", "Root directory for results (default ./out)") do |dest|
    options.out = dest
  end
  opts.on("-f", "--filter PATH", "Part of source path that acts as filter") do |filter|
    options.filter = filter
  end
  opts.on_tail("-h", "--help", "Help") do
    puts opts
    exit
  end
  opts.on_tail("-u", "--update", "Force") do

  end
end
parser.parse!
unless ARGV.grep(/^-u/).empty?
  options.force = true
end
options.force = true
if options.src.nil?
  puts parser
  raise "Missed argument -s (Source directory)"
end
processor = Translate.new(options.src, options.out, options.filter, options.force)
processor.start

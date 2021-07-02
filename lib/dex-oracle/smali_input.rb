require 'zip'
require 'English'
require_relative 'utility'
require_relative 'logging'

class SmaliInput
  attr_reader :dir, :out_apk, :out_dex_array, :temp_dir, :temp_dex

  include Logging

  DEX_MAGIC = [0x64, 0x65, 0x78].freeze
  PK_ZIP_MAGIC = [0x50, 0x4b, 0x3].freeze

  def initialize(input)
    prepare(input)
  end

  def finish
    SmaliInput.update_apk(dir, @out_apk) if @out_apk
    SmaliInput.compile(dir, @out_dex) if @out_dex && !@out_apk
    FileUtils.rm_rf(@dir) if @temp_dir
    @out_dex_array.each { |n, f| n.each { |name, file| FileUtils.rm_rf(file) if @temp_dex } }    
  end

  def self.compile(dir, out_dex = nil)
    raise 'Smali could not be found on the path.' if Utility.which('smali').nil?
    out_dex = Tempfile.new(%w(oracle .dex)) if out_dex.nil?
    logger.info("Compiling DEX #{out_dex.path} ... #{dir}")
    exit_code = SmaliInput.exec("smali assemble -o #{out_dex.path} #{dir}")
    # Remember kids, if you make a CLI, exit with non-zero status for failures
    raise 'Crap, smali compilation failed.' if $CHILD_STATUS.exitstatus != 0
    out_dex
  end

  def self.update_apk(dir, out_apk)
    out_dex = compile(dir)
    Utility.update_zip(out_apk, 'classes.dex', out_dex)
  end

  def self.extract_dexes(apk, out_dex_array)
    # Extract all dex, dont do just one dudeeee.
    Utility.extract_dexes(apk, out_dex_array)
  end

  def self.exec(cmd)
    `#{cmd}`
  end

  private

  def baksmali(input)
    logger.debug("Disassembling #{input} ...")
    raise 'Baksmali could not be found on the path.' if Utility.which('baksmali').nil?
    cmd = "baksmali disassemble --debug-info false --output #{@dir} #{input}"
    SmaliInput.exec(cmd)
  end
  def baksmali_list_dex(input)
    raise 'Baksmali could not be found on the path.' if Utility.which('baksmali').nil?
    cmd = "baksmali list dex #{input}"
    output = SmaliInput.exec(cmd)
    logger.debug("APK Contains : #{output.split("\n")}")
    output.split("\n")
  end
  def prepare(input)
    if File.directory?(input)
      @temp_dir = false
      @temp_dex = true
      @dir = input
      @out_dex = SmaliInput.compile(dir)
      return
    end

    magic = File.open(input) { |f| f.read(3) }.bytes.to_a
    case magic
    when PK_ZIP_MAGIC
      @temp_dex = true
      @temp_dir = true
      @out_apk = "#{File.basename(input, '.*')}_oracle#{File.extname(input)}"
      FileUtils.cp(input, @out_apk)
      @out_dex_array = []
      SmaliInput.extract_dexes(@out_apk,@out_dex_array)
      baksmali_dex_list = baksmali_list_dex(input)
      @dir = Dir.mktmpdir
      baksmali_dex_list.each do |inner_dex|
        baksmali(input+"/"+inner_dex)
      end
    when DEX_MAGIC
      @temp_dex = false
      @temp_dir = true
      @out_dex = "#{File.basename(input, '.*')}_oracle#{File.extname(input)}"
      FileUtils.cp(input, @out_dex)
      @out_dex = File.new(@out_dex)
      @out_dex_array = []
      @out_dex_array.append("classes.dex" => @out_dex)
      @dir = Dir.mktmpdir
      baksmali(input)
    else
      raise "Unrecognized file type for: #{input}, magic=#{magic.inspect}"
    end
  end
end

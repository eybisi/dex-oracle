require_relative '../logging'
require_relative '../utility'

class PackerKiller < Plugin
  attr_reader :optimizations

  include Logging
  include CommonRegex

  KILLER_DECRYPT = Regexp.new(
    '^[ \t]*(' +
    'const-string(?:/jumbo)? ([vp]\d+), "(.*?)"' + '\s+' \
    'invoke-(virtual|direct) \{[vp]\d+, \2\}, L([^;]+);->([^\(]+\(Ljava/lang/String;\))Ljava/lang/String;' \
    '\s+)'
   # MOVE_RESULT_OBJECT + ")"
  )

  MODIFIER = -> (_, output, input_reg) { "const-string #{input_reg}, \"#{output.split('').collect { |e| e.inspect[1..-2] }.join}\""\
  "\ninvoke-virtual \{#{input_reg}\}, Ljava\/lang\/String;->toString\(\)Ljava\/lang\/String;"}

  def initialize(driver, smali_files, methods)
    @driver = driver
    @smali_files = smali_files
    @methods = methods
    @optimizations = Hash.new(0)
  end

  def process
    method_to_target_to_contexts = {}
    @methods.each do |method|
      logger.info("Killing bad strings #{method.descriptor}")
      target_to_contexts = {}
      target_to_contexts.merge!(decrypt_strings(method))
      target_to_contexts.map { |_, v| v.uniq! }
      method_to_target_to_contexts[method] = target_to_contexts unless target_to_contexts.empty?
    end

    made_changes = false
    made_changes |= Plugin.apply_batch(@driver, method_to_target_to_contexts, MODIFIER)

    made_changes
  end

  private

  def decrypt_strings(method)
    target_to_contexts = {}
    matches = method.body.scan(KILLER_DECRYPT)
    @optimizations[:string_decrypts] += matches.size if matches
    matches.each do |original, input_reg, encrypted, call_type,class_name, method_signature|
        #logger.info(" packerrrrrrr #{original}")
        target = @driver.make_instance_target(
        class_name, method_signature, encrypted
      )
      target_to_contexts[target] = [] unless target_to_contexts.key?(target)
      target_to_contexts[target] << [original, input_reg]
    end

    target_to_contexts
  end
end

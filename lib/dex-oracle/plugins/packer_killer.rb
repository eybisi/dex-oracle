require_relative '../logging'
require_relative '../utility'

class PackerKiller < Plugin
  attr_reader :optimizations

  include Logging
  include CommonRegex

  KILLER_DECRYPT = Regexp.new(
    '^[ \t]*(' +
    'const-string(?:/jumbo)? ([vp]\d+), "(.*?)"' + '\s+' \
    'invoke-(virtual|direct) \{[vp]\d+, [vp]\d+}, L([^;]+);->([^\(]+\(Ljava/lang/String;\))Ljava/lang/String;\s+' \
    'move-result-object ([vp]\d+))'
  )
  KILLER_DECRYPT_2 = Regexp.new(
    '^[ \t]*(' +
    'const-string(?:/jumbo)? ([vp]\d+), "(.*?)"' + '\s+' \
    'move-object\/from16 [vp]\d+, [vp]\d+\s+'\
    'move-object\/from16 [vp]\d+, [vp]\d+\s+'\
    'invoke-(virtual|direct) \{[vp]\d+, [vp]\d+}, L([^;]+);->([^\(]+\(Ljava/lang/String;\))Ljava/lang/String;\s+' \
    'move-result-object ([vp]\d+))'
  )


  MODIFIER = -> (_, output, input_reg) { "const-string #{input_reg}, \"#{output.split('').collect { |e| e.inspect[1..-2] }.join}\""}
  #"\ninvoke-virtual \{#{input_reg}\}, Ljava\/lang\/String;->toString\(\)Ljava\/lang\/String;"}

  def initialize(driver, smali_files, methods)
    @driver = driver
    @smali_files = smali_files
    @methods = methods
    @optimizations = Hash.new(0)
  end

  def process
    method_to_target_to_contexts = {}
    @activity_list = []
    @smali_files.each do |smali|
      @is_activity = false
      # logger.info("smali loop #{smali.class} #{smali.super}")
      @current_class = smali.class
      if smali.super == "Landroid/app/Activity;"
        @activity_list.append(smali.class)
        @is_activity = true
      end  
      smali.methods.each do |method| 
        target_to_contexts = {}
        target_to_contexts.merge!(decrypt_strings(method))
        target_to_contexts.map { |_, v| v.uniq! }
        method_to_target_to_contexts[method] = target_to_contexts unless target_to_contexts.empty?
      end
    end

    made_changes = false
    made_changes |= Plugin.apply_batch(@driver, method_to_target_to_contexts, MODIFIER)

    made_changes
  end

  private

  def decrypt_strings(method)
    target_to_contexts = {}
    matches = method.body.scan(KILLER_DECRYPT)
    matches += method.body.scan(KILLER_DECRYPT_2)
    @optimizations[:string_decrypts] += matches.size if matches
    matches.each do |original, input_reg, encrypted, call_type,class_name, method_signature,output_reg|
      if class_name != "android/content/Intent" and class_name != "org/json/JSONObject"
        if @is_activity or ( 
          @activity_list.include? @current_class.to_s.split("$").first+";" and
          @current_class.to_s.split("$").length() > 1
          )
          target = @driver.make_instance_target(
          @decryptor_class, @decryptor_method, encrypted
        )
        else
          @decryptor_class = class_name
          @decryptor_method = method_signature 
          target = @driver.make_instance_target(
          class_name, method_signature, encrypted
          )
        end
        target_to_contexts[target] = [] unless target_to_contexts.key?(target)
        target_to_contexts[target] << [original, output_reg]
      end
    end

    target_to_contexts
  end
end

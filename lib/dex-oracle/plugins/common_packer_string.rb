require_relative '../logging'
require_relative '../utility'

class CommonPackerString < Plugin
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
    @is_set = false
  end

  def process
    method_to_target_to_contexts = {}
    @activity_list = []
    @smali_files.each do |smali|
      @is_activity = false
      # logger.info("smali loop #{smali.class} #{smali.super}")
      @current_smali = smali
      if smali.super == "Landroid/app/Activity;"
        @activity_list.append(smali.class.to_s.split(";").first)
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


  def decrypt_strings(method)
    target_to_contexts = {}
    matches = method.body.scan(KILLER_DECRYPT)
    matches += method.body.scan(KILLER_DECRYPT_2)
    matches.each do |original, input_reg, encrypted, call_type,class_name, method_signature,output_reg|
      if class_name != "android/content/Intent" and class_name != "org/json/JSONObject" and class_name != 'android/text/format/Time' and class_name != "java/lang/String"
        if @is_activity or ( 
          @activity_list.include? @current_smali.class.to_s.split("$").first and
          @current_smali.class.to_s.split("$").length() > 1
          ) or !@current_smali.content.include? "constructor <init>()V" or @current_smali.content.include? ".class final" and @is_set
          # logger.info("Decryptor class" + @current_smali.class + ";"+@decryptor_class+";"+ @decryptor_method)
          target = @driver.make_instance_target(
          @decryptor_class, @decryptor_method, encrypted
        )
        @optimizations[:common_packer_string] +=1
        else
          # If its not public class, we cant access it.
          # TODO Need to check against class that will be initialized by driver
          # It doesn't need to be same as method's class.
          #       
          @decryptor_class = class_name
          @decryptor_method = method_signature
          @is_set = true
          # logger.info("Decryptor2 class" + ";"+ class_name + ";"+method_signature)
          target = @driver.make_instance_target(
          class_name, method_signature, encrypted
          )
          @optimizations[:common_packer_string] += 1
          # else
            # next
          # end
        end
        target_to_contexts[target] = [] unless target_to_contexts.key?(target)
        target_to_contexts[target] << [original, output_reg]
      end
    end

    target_to_contexts
  end
end

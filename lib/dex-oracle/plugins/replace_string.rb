require_relative '../logging'
require_relative '../utility'

=begin

2 common patterns:
    const-string v16, "drDRFTFYUIASFIBGAUIGFBUIABGUIASGIUawDRFTFYUIASFIBGAUIGFBUIABGUIASGIUabDRFTFYUIASFIBGAUIGFBUIABGUIASGIUle"
    const-string v17, "DRFTFYUIASFIBGAUIGFBUIABGUIASGIU"
    const-string v18, ""
    invoke-virtual/range {v16 .. v18}, Ljava/lang/String;->replace(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;
    move-result-object v16

    const-string v2, "oDERFTGYHUJIU&^Y%$FGYUnCrDERFTGYHUJIU&^Y%$FGYUeate"
    const-string v3, "DERFTGYHUJIU&^Y%$FGYU"
    const-string v4, ""
    invoke-virtual {v2, v3, v4}, Ljava/lang/String;->replace(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;
    move-result-object v2

My idea is that dont bother with creating string instances then calling the replace function. Just do that here.
Note that move-result-object's register is same as first string's register which is usefull for us. We can just replace all of that with just
const-string vX, RESULT_STRING

=end

class ReplaceString < Plugin
  attr_reader :optimizations

  include Logging
  include CommonRegex
  

  REPLACER = Regexp.new(
    '^[ \t]*(' \
    '(const-string [vp]\d+, "(.*?)".*\s+)' \
    'const-string [vp]\d+, "(.*?)".*\s+' \
    'const-string [vp]\d+, "(.*?)".*\s+' \
    'invoke-virtual\/range \{[vp]\d+ .. [vp]\d+\}' \
    ', Ljava\/lang\/String;->replace\(Ljava\/lang\/CharSequence;Ljava\/lang\/CharSequence;\)Ljava\/lang\/String;\s+move-result-object ([vp]\d+))'
  )

  # Im lazy, you can probably do this in same regex.
  REPLACER2 = Regexp.new(
    '^[ \t]*(' \
    '(const-string [vp]\d+, "(.*?)".*\s+)' \
    'const-string [vp]\d+, "(.*?)".*\s+' \
    'const-string [vp]\d+, "(.*?)".*\s+' \
    'invoke-virtual \{[vp]\d+, [vp]\d, [vp]\d+\}' \
    ', Ljava\/lang\/String;->replace\(Ljava\/lang\/CharSequence;Ljava\/lang\/CharSequence;\)Ljava\/lang\/String;\s+move-result-object ([vp]\d+))'
  )

  MODIFIER = -> (_, output, input_reg) { "const-string #{input_reg}, \"#{output.split('').collect { |e| e.inspect[1..-2] }.join}\""}

  def initialize(driver, smali_files, methods)
    @driver = driver
    @smali_files = smali_files
    @methods = methods
    @optimizations = Hash.new(0)
  end

  def process
    method_to_target_to_contexts = {}
    made_changes = false
    @methods.each do |method|
      logger.info("Replacing strings #{method.descriptor}")
      target_to_contexts = {}
      target_to_contexts.merge!(replace_strings(method))
      target_to_contexts.map { |_, v, _| v.uniq! }
      method_to_target_to_contexts[method] = target_to_contexts unless target_to_contexts.empty?
    end
    method_to_target_to_contexts.each do |method, target_to_contexts|
        target_to_contexts.each do |target, contexts|
            contexts.each do |original, replaced, output_reg|
                modification = MODIFIER.call(original, replaced, output_reg)
                dumb_replace(method.body, original, modification)
                made_changes = true
                method.modified = true
            end
        end
    end

    made_changes
  end

  private

  def replace_strings(method)
    target_to_contexts = {}
    matches = method.body.scan(REPLACER)
    matches =+ method.body.scan(REPLACER2)
    @optimizations[:string_replace] += matches.size if matches
    matches.each do |original,_,input_string,replace,with,output_reg|
        target = @driver.make_instance_target(
            original, input_string, output_reg
      )
      target_to_contexts[target] = [] unless target_to_contexts.key?(target)
      target_to_contexts[target] << [original, dumb_replace(input_string,replace,with), output_reg]
    end
    target_to_contexts
  end

  def dumb_replace(string, find, replace)
    string[find] = replace while string.include?(find)
    string
  end
end


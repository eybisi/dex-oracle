require_relative '../logging'
require_relative '../utility'

=begin
sample : ea4ad603aa162d34b108b4649583c20f63ed756d6ec2a2ca656e3abebb8f4369

smali : 
    const-string v0, ""
    invoke-static {}, Lˋˆיᴵˊﹳﹳﹳᵔˉ/ˊᵢʾˆʾˋʼˈʾˈˈـ/ᵔˈʾᵎﹳˊˉʿᴵˊˊʿי/ˎˏﹶˉʼʻᵎˈʽʽ;->gElYNـﾞﾞᵎʾˆˋʾᵔˆⁱˉˏⁱᴵˆיjGOBE()Ljava/lang/String;
    move-result-object v0

method:
    same as static function replacing. Move result as const string

=end



class UnprintableClassStaticString < Plugin
  attr_reader :optimizations

  include Logging
  include CommonRegex

  STRING_DECRYPT = Regexp.new(
    '^[ \t]*(' +
    'const-string(?:/jumbo)? ([vp]\d+), ""' + '\s+' \
    'invoke-static \{\}, L([^;]+);->([^\(]+\(\))Ljava/lang/String;\s+' \
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
    @methods.each do |method| 
        target_to_contexts = {}
        target_to_contexts.merge!(decrypt_strings(method))
        target_to_contexts.map { |_, v| v.uniq! }
        method_to_target_to_contexts[method] = target_to_contexts unless target_to_contexts.empty?
    end

    made_changes = false
    made_changes |= Plugin.apply_batch(@driver, method_to_target_to_contexts, MODIFIER)

    made_changes
  end


  def decrypt_strings(method)
    target_to_contexts = {}
    matches = method.body.scan(STRING_DECRYPT)
    matches.each do |original, input_reg,class_name, method_signature,output_reg|
        # logger.info(class_name + " " + method_signature + " " + output_reg)
        target = @driver.make_target(
        class_name, method_signature
        )
        @optimizations[:string_decrypts] += 1

        target_to_contexts[target] = [] unless target_to_contexts.key?(target)
        target_to_contexts[target] << [original, output_reg]
      
    end

    target_to_contexts
  end
end

require_relative '../logging'
require_relative '../utility'

class CharArrayString < Plugin
  attr_reader :optimizations

  include Logging
  include CommonRegex
=begin
    new-array v0, v0, [C
    fill-array-data v0, :array_17a
    invoke-static {v0}, Ljava/lang/String;->valueOf([C)Ljava/lang/String;

=end

  CHAR_ARRAY_REGEX = Regexp.new(
    '^[ \t]*(' +
    # 'const\/16 [vp]\d+, 0x\w+\s+' \
    'new-array ([vp]\d+), ([vp]\d+), \[C\s+' \
    'fill-array-data ([vp]\d+), :(array\_\w+)\s+'\
    'invoke-static \{([vp]\d+)\}, Ljava\/lang\/String;->valueOf\(\[C\)Ljava\/lang\/String;\s+'\
    'move-result-object ([vp]\d+))'
  )
  
  FIND_ARRAY_REGEX = Regexp.new(
    '\s+\.array-data \d+\s+'\
    '((0x\w\ws\s+)+)'
    #'([(0x\w\w)s\s+]{1,50})'
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
    made_changes = false
    @smali_files.each do |smali|
      @current_smali = smali
      smali.methods.each do |method| 
          # logger.info("char value replace #{method.descriptor}")
          made_changes |= decrypt_strings(method)
      end
    end

    made_changes
  end


  def decrypt_strings(method)
    target_to_contexts = {}
    target_id_to_output = {}
    matches = method.body.scan(CHAR_ARRAY_REGEX)
    
    matches.each do |full,array_reg,array_reg2,fill_reg,data_array,invoke_reg,result_reg|
        # logger.info(method.body)

        d =  Regexp.new(data_array.sub! '_', '\_')
        search_array = Regexp.new(d.source + FIND_ARRAY_REGEX.source)
        array_regex = @current_smali.content.scan(search_array)
        array_regex.each do |contents_with_newl|
            target = { id: Digest::SHA256.hexdigest(full) }
            # logger.info(contents_with_newl)
            contents_with_newl[0].gsub! ' ',''
            contents_with_newl[0].gsub! 's',''
            contents_with_newl[0].gsub! '0x',''
            splitted_data_array = contents_with_newl[0].split(/\n/)
            
            final_string = [splitted_data_array.join("")].pack("H*")
            logger.info(final_string)
            target_id_to_output[target[:id]] = ['success', final_string]
            target_to_contexts[target] = [] unless target_to_contexts.key?(target)
            target_to_contexts[target] << [full, result_reg]
            @optimizations[:char_replace] += 1
        end
    end

    method_to_target_to_contexts = { method => target_to_contexts }
    Plugin.apply_outputs(target_id_to_output, method_to_target_to_contexts, MODIFIER)
  end
end

require_relative '../logging'
require_relative '../utility'

class IndexedClassLookup < Plugin
  attr_reader :optimizations

  include Logging
  include CommonRegex

  CLASS_DECRYPT = Regexp.new(
    '^[ \t]*(' +
    CONST_NUMBER_CAPTURE + '\s+' +
    '(?:\:[^\n]+\n\s*)?' + # May have a label between const and invoke
    'invoke-static \{\2\}, L([^;]+);->([^\(]+\(I\))Ljava/lang/Class;' \
    '\s+' +
    MOVE_RESULT_OBJECT + ')'
  )
  CLASS_DECRYPT2 = Regexp.new(
    '^[ \t]*(' \
    'const-string(?:/jumbo)? [vp]\d+, "(.*?)"\s+' \
    'invoke-static \{[vp]\d+\}, L([^;]+);->([^\(]+\(Ljava/lang/String;\))Ljava/lang/Class;\s+'\
    'move-result-object ([vp]\d+))'
  )

  MODIFIER = -> (original, output, out_reg) do
    # Put the labels back if any were removed
    labels = original.split("\n").select { |l| l.lstrip.start_with?(':') }
    labels << "\n    " unless labels.empty?
    "#{labels.join("\n")}const-class #{out_reg}, #{output.split('').collect { |e| e.inspect[1..-2] }.join}"
  end
  MODIFIER2 = -> (_, output, input_reg) { "const-class #{input_reg}, #{output.split('').collect { |e| e.inspect[1..-2] }.join}"}
  # Sometimes class name lookup doesn't work and null is returned
  FILTER = -> (_, output, out_reg) { output == 'null' }

  def initialize(driver, smali_files, methods)
    @driver = driver
    @smali_files = smali_files
    @methods = methods
    @optimizations = Hash.new(0)
  end

  def process
    method_to_target_to_contexts = {}
    @methods.each do |method|
      logger.info("Decrypting indexed classes #{method.descriptor}")
      target_to_contexts = {}
      target_to_contexts.merge!(decrypt_classes(method))
      target_to_contexts.map { |_, v| v.uniq! }
      method_to_target_to_contexts[method] = target_to_contexts unless target_to_contexts.empty?
    end

    made_changes = false
    made_changes |= Plugin.apply_batch(@driver, method_to_target_to_contexts, MODIFIER, FILTER)

    @methods.each do |method|
      logger.info("decrypt_classes2 #{method.descriptor}")
      made_changes |= decrypt_classes2(method)
    end

    made_changes
  end

  private

  def decrypt_classes(method)
    target_to_contexts = {}
    matches = method.body.scan(CLASS_DECRYPT)
    
    @optimizations[:class_lookups] += matches.size if matches
    matches.each do |original, _, class_index, class_name, method_signature, out_reg|
      target = @driver.make_target(
        class_name, method_signature, class_index.to_i(16)
      )
      target_to_contexts[target] = [] unless target_to_contexts.key?(target)
      target_to_contexts[target] << [original, out_reg]
    end
    target_to_contexts
  end
  
  def decrypt_classes2(method)

    target_to_contexts = {}
    target_id_to_output = {}
    matches = method.body.scan(CLASS_DECRYPT2)
    
    @optimizations[:class_lookups_2] += matches.size if matches
    matches.each do |original, return_class, class_name, method_signature, out_reg|
      if class_name == "[B"
        next
      else
        target = { id: Digest::SHA256.hexdigest(original) }
        smali_class = "L#{return_class.tr('.', '/')};"
        logger.info("len!! " + out_reg + "\n#####\n"+ smali_class + "\n#####\n")
        target_id_to_output[target[:id]] = ['success', smali_class]
        target_to_contexts[target] = [] unless target_to_contexts.key?(target)
        target_to_contexts[target] << [original, out_reg]
        @optimizations[:class_lookups_2] += 1
      end
    end

    method_to_target_to_contexts = { method => target_to_contexts }
    Plugin.apply_outputs(target_id_to_output, method_to_target_to_contexts, MODIFIER2)
  end
end

require_relative '../logging'
require_relative '../utility'

class StringDecryptor < Plugin
  attr_reader :optimizations

  include Logging
  include CommonRegex

  STRING_DECRYPT = Regexp.new(
    '^[ \t]*(' +
    CONST_STRING_CAPTURE + '\s+' \
    'invoke-static \{\2\}, L([^;]+);->([^\(]+\(Ljava/lang/String;\))Ljava/lang/String;' \
    '\s+' +
    MOVE_RESULT_OBJECT + ')'
  )
  STRING_DECRYPT1 = Regexp.new(
    '^[ \t]*(' +
    CONST_STRING_CAPTURE + '\s+' \
    'invoke-static \{\2\}, L([^;]+);->([^\(]+\(Ljava/lang/Object;\))Ljava/lang/String;' \
    '\s+' +
    MOVE_RESULT_OBJECT + ')'
  )
  STRING_DECRYPT2 = Regexp.new(
    '^[ \t]*(' +
    'const [vp]\d+, (-?0x[a-f\d]+)' + '\s+' +
    'const [vp]\d+, (-?0x[a-f\d]+)' + '\s+' +
    'const [vp]\d+, (-?0x[a-f\d]+)' + '\s+' +
    'invoke-static\/range \{[vp]\d+, [vp]\d+, [vp]\d+\}, L([^;]+);->([^\(]+\(III\))Ljava/lang/String;\s+' \
    'move-result-object ([vp]\d+))'
  )
  STRING_DECRYPT3 = Regexp.new(
    '^[ \t]*(' +
    'const [vp]\d+, (-?0x[a-f\d]+)' + '\s+' +
    'const [vp]\d+, (-?0x[a-f\d]+)' + '\s+' +
    'const [vp]\d+, (-?0x[a-f\d]+)' + '\s+' +
    'invoke-static\/range \{[vp]\d+ \.\. [vp]\d+\}, L([^;]+);->([^\(]+\(III\))Ljava/lang/String;\s+' \
    'move-result-object ([vp]\d+))'
  )
  #34c5c4d996b33eb842d38507bf2f1a0728500c7b705407826d8196d3bc6e571b Long value to String with Static function
  STRING_DECRYPT4 = Regexp.new(
    '^[ \t]*(' +
    'const-wide [vp]\d+, (-?0x[a-f\d]+L)' + '\s+' +
    'invoke-static\/range \{[vp]\d+ \.\. [vp]\d+\}, L([^;]+);->([^\(]+\(J\))Ljava/lang/String;\s+' \
    'move-result-object ([vp]\d+))'
  )
  #34c5c4d996b33eb842d38507bf2f1a0728500c7b705407826d8196d3bc6e571b Long value to String with Static function
  STRING_DECRYPT5 = Regexp.new(
    '^[ \t]*(' +
    'const-wide [vp]\d+, (-?0x[a-f0-9]+L)' + '\s+' +
    'invoke-static \{[vp]\d+, [vp]\d+\}, L([^;]+);->([^\(]+\(J\))Ljava\/lang\/String;\s+' +
    'move-result-object ([vp]\d+))'
  )

  #a772327f34456de80abaa43838d490751af5315865ee58208062e97b91b0153c
  # #const/16 v0, 0x123
  # #invoke-static {v0}, Lcom/brazzers/naughty/g;->a(I)Ljava/lang/String;
  # #move-result-object v0
  STRING_DECRYPT6 = Regexp.new(
    '^[ \t]*(' +
    'const\/16 [vp]\d+, (-?0x[a-f\d]+)' + '\s+' +
    'invoke-static \{[vp]\d+}, L([^;]+);->([^\(]+\(I\))Ljava/lang/String;\s+' \
    'move-result-object ([vp]\d+))'
  )
  STRING_DECRYPT7 = Regexp.new(
    '^[ \t]*(' +
    'const-wide [vp]\d+, (-?0x[a-f0-9]+L)    # ?-\d\.\d+E\d+' + '\s+' +
    'invoke-static \{[vp]\d+, [vp]\d+\}, L([^;]+);->([^\(]+\(J\))Ljava\/lang\/String;\s+' +
    'move-result-object ([vp]\d+))'
  )



  MODIFIER = -> (_, output, out_reg) { "const-string #{out_reg}, \"#{output.split('').collect { |e| e.inspect[1..-2] }.join}\"" }

  def initialize(driver, smali_files, methods)
    @driver = driver
    @smali_files = smali_files
    @methods = methods
    @optimizations = Hash.new(0)
  end

  def process
    method_to_target_to_contexts = {}
    @methods.each do |method|
      # logger.info("Decrypting strings #{method.descriptor}")
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
    matches = method.body.scan(STRING_DECRYPT)
    @optimizations[:string_decrypts] += matches.size if matches
    matches.each do |original, _, encrypted, class_name, method_signature, out_reg|
      if encrypted.include? "\\"
        # logger.info("wtf java string " + encrypted)
        encrypted = encrypted.gsub("\\\\","\\")
        # logger.info("wtf java string " + encrypted.gsub("\\\\","\\"))
        # logger.info("wtf java string " + encrypted)
      end
      target = @driver.make_target(
        class_name, method_signature, encrypted
      )
      target_to_contexts[target] = [] unless target_to_contexts.key?(target)
      target_to_contexts[target] << [original, out_reg]
    end
    matches = method.body.scan(STRING_DECRYPT1)
    @optimizations[:string_decrypts] += matches.size if matches
    matches.each do |original, _, encrypted, class_name, method_signature, out_reg|

      if encrypted.include? "\\"
        logger.info("wtf java string " + encrypted)
        # encrypted = encrypted.gsub("\\\\","\\")
        # logger.info("wtf java string " + encrypted.gsub("\\\\","\\"))
        # logger.info("wtf java string " + encrypted)
      end
      target = @driver.make_target(
        class_name, method_signature, encrypted
      )
      target_to_contexts[target] = [] unless target_to_contexts.key?(target)
      target_to_contexts[target] << [original, out_reg]
      
    end
    matches = method.body.scan(STRING_DECRYPT2)
    @optimizations[:string_decrypts] += matches.size if matches
    matches.each do |original, number1, number2, number3, class_name, method_signature, out_reg|
      # logger.info("New" + " " + number1 + " " + number2 + " " + number3 + " " + number1+ " " + class_name + " " + method_signature + " " + out_reg)
      target = @driver.make_target(
        class_name, method_signature, number1.to_i(16),number2.to_i(16),number3.to_i(16)
      )
      target_to_contexts[target] = [] unless target_to_contexts.key?(target)
      target_to_contexts[target] << [original, out_reg]
    end

    matches = method.body.scan(STRING_DECRYPT3)
    @optimizations[:string_decrypts] += matches.size if matches
    matches.each do |original, number1, number2, number3, class_name, method_signature, out_reg|
      # logger.info("New2" + " " + number1 + " " + number2 + " " + number3 + " " + number1+ " " + class_name + " " + method_signature + " " + out_reg)
      target = @driver.make_target(
        class_name, method_signature, number1.to_i(16),number2.to_i(16),number3.to_i(16)
      )
      target_to_contexts[target] = [] unless target_to_contexts.key?(target)
      target_to_contexts[target] << [original, out_reg]
    end

    matches = method.body.scan(STRING_DECRYPT4)
    @optimizations[:string_decrypts] += matches.size if matches
    matches.each do |original, long, class_name, method_signature, out_reg|
      # logger.info("New3" + " " + long + " " + class_name + " " + method_signature + " " + out_reg)
      target = @driver.make_target(
        class_name, method_signature, long.to_i(16)
      )
      target_to_contexts[target] = [] unless target_to_contexts.key?(target)
      target_to_contexts[target] << [original, out_reg]
    end
    # logger.info(method.body)
    matches = method.body.scan(STRING_DECRYPT5)
    @optimizations[:string_decrypts] += matches.size if matches
    matches.each do |original, long, class_name, method_signature, out_reg|
      logger.info("New3" + " " + long + " " + class_name + " " + method_signature + " " + out_reg)
      target = @driver.make_target(
        class_name, method_signature, long.to_i(16)
      )
      target_to_contexts[target] = [] unless target_to_contexts.key?(target)
      target_to_contexts[target] << [original, out_reg]
    end

    matches = method.body.scan(STRING_DECRYPT6)
    @optimizations[:string_decrypts] += matches.size if matches
    matches.each do |original, int, class_name, method_signature, out_reg|
      # logger.info("NewX" + " " + int + " " + class_name + " " + method_signature + " " + out_reg)
      target = @driver.make_target(
        class_name, method_signature, int.to_i(16)
      )
      target_to_contexts[target] = [] unless target_to_contexts.key?(target)
      target_to_contexts[target] << [original, out_reg]
    end

    matches = method.body.scan(STRING_DECRYPT7)
    @optimizations[:string_decrypts] += matches.size if matches
    matches.each do |original, int, class_name, method_signature, out_reg|
      logger.info("NewX" + " " + int + " " + class_name + " " + method_signature + " " + out_reg)
      target = @driver.make_target(
        class_name, method_signature, int.to_i(16)
      )
      target_to_contexts[target] = [] unless target_to_contexts.key?(target)
      target_to_contexts[target] << [original, out_reg]
    end
    target_to_contexts


  end
end

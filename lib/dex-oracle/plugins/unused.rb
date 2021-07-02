require 'digest'
require_relative '../logging'
require 'set'

class Unused < Plugin
  attr_reader :optimizations

  include Logging
  include CommonRegex

  CLASS_USED_REGEX = Regexp.new(
      ' L([^;]+);'
  )


  def initialize(driver, smali_files, methods)
    @driver = driver
    @smali_files = smali_files
    @methods = methods
    @optimizations = Hash.new(0)
  end

  def process
    #Put packer's Application class or All activities here.
    #2685bb2718ca6d127939f4d1e6e4d21f8bceb82613f4e475c99b8dc3b3325f82
    class_list = Set["owner/walk/disorder/HUyUnSdOeEcYrAwLxPwMsFu"]
    processed_class = Set[]
    # Walk all smali files.
    # Extract used CLASSES
    # - Regex for L([^;]+);


    # Application Class:
    # -> find refs
    # loop


    found_new_class = true
    while found_new_class
        found_new_class = false
        @smali_files.each do |smali|
            new_class_list = Set[*class_list]
            class_list.each do |whitelist_class|
                if smali.file_path.include? whitelist_class
                    if !processed_class.include? smali.file_path
                        matches = smali.content.scan(CLASS_USED_REGEX)
                        # logger.info("#{matches}")
                        matches.each do |class_name|
                            if !class_name[0].start_with?("java/","dalvik/")
                                found_new_class = true
                                new_class_list.add(class_name[0])
                            end
                            # logger.info("#{class_name[0]}")
                        end
                            
                        logger.info("new list #{new_class_list}")
                    end
                        processed_class.add(smali.file_path)  
                class_list = new_class_list 
                end
            end
        end
    end
    
    made_changes = false


    @smali_files.each do |smali|
        delete_me = true
        class_list.each do |whitelist_class|
            if smali.file_path.include? whitelist_class
                delete_me = false
                break    
            end
        end
        if delete_me
            # logger.info("removing #{smali.file_path}")
            FileUtils.rm_rf(smali.file_path)
        else
            logger.info("not removing #{smali.file_path}")
        end

    end
    
    made_changes = false
    
  end

end

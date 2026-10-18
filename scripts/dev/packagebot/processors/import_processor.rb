require 'set'
require_relative '../logger'

class ImportProcessor
  include PackageBot
  
  def initialize(configuration)
    @configuration = configuration
  end

  def process_target_imports
    target_import_data = initialize_import_data
    
    @configuration["LAYERS"].each do |layer|
      process_layer(layer, target_import_data)
    end
    
    summarize_import_stats(target_import_data)
    report_unmapped_imports(target_import_data[:unmapped_imports])
    target_import_data
  end

  private

  def initialize_import_data
    {
      all_imports: {},
      unmapped_imports: {},
      processed_imports: {}
    }
  end

  def process_layer(layer, target_import_data)
    target_import_data[:processed_imports][layer.name] = {}
    
    layer.packages.each do |package|
      process_package(layer.name, package, target_import_data)
    end
  end

  def process_package(layer_name, package, target_import_data)
    target_import_data[:processed_imports][layer_name][package.name] = {}
    
    package.targets.each do |target|
      process_target(layer_name, package, target, target_import_data)
    end
  end

  def process_target(layer_name, package, target, target_import_data)
    LOGGER.verbose("Processing target: #{target.name}")
    
    # Process main target imports
    imports, imports_by_file = find_imports_in_target(target.relative_path, package.path)
    target_import_data[:all_imports][target.name] = imports.uniq.sort
    
    # Process test imports if they exist
    test_imports, test_imports_by_file = find_test_imports(package.path)
    if test_imports.any?
      # Store test imports separately instead of merging
      target_import_data[:all_imports]["#{target.name}Tests"] = test_imports.uniq.sort
      
      # Store main target and test imports separately
      store_processed_imports(layer_name, package, target, [imports, imports_by_file], target_import_data)
      store_processed_imports(layer_name, package, target, [test_imports, test_imports_by_file], target_import_data, is_test: true)
      
      # Process mappings separately
      process_import_mappings(layer_name, package, target, imports, target_import_data)
      process_import_mappings(layer_name, package, target, test_imports, target_import_data, is_test: true)
    else
      store_processed_imports(layer_name, package, target, [imports, imports_by_file], target_import_data)
      process_import_mappings(layer_name, package, target, imports, target_import_data)
    end
  end

  def find_imports_in_target(target_path, package_path)
    LOGGER.verbose("Processing imports for #{target_path} in #{package_path}")
    
    full_path = "#{package_path}/#{target_path}"
    command = "cd #{full_path} && grep -rlE --include='*.swift' '^[[:space:]]*(@[[:alnum:]_]+[[:space:]]+)?((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]' ."
    
    begin
      files = `#{command}`.strip.split("\n").map { |f| f.sub(%r{^\./}, "") }
      imports_by_file = {}
      
      files.each do |file|
        file_content = File.read(File.join(full_path, file))
        
        imports = file_content.scan(/^[[:space:]]*(?:@.*?[[:space:]]+)?(?:(?:public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+([^\n\/]+)/)
                             .flatten
                             .map(&:strip)
                             .map { |imp| imp.sub(/^(class|struct|enum)\s+([^\.]+)\..*$/, '\2') }
        
        imports_by_file[file] = imports unless imports.empty?
      end
      
      [imports_by_file.values.flatten, imports_by_file]
    rescue => e
      LOGGER.error("Error processing imports: #{e.message}")
      [[], {}]
    end
  end

  def find_test_imports(package_path)
    test_path = "#{package_path}/Tests"
    return [[], {}] unless Dir.exist?(test_path)
    
    command = "cd #{test_path} && grep -rlE --include='*.swift' '^[[:space:]]*(@[[:alnum:]_]+[[:space:]]+)?((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]' ."
    
    begin
      files = `#{command}`.strip.split("\n").map { |f| f.sub(%r{^\./}, "") }
      imports_by_file = {}
      
      files.each do |file|
        file_content = File.read(File.join(test_path, file))

        imports = file_content.scan(/^[[:space:]]*(?:@.*?[[:space:]]+)?(?:(?:public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+([^\n\/]+)/)
                             .flatten
                             .map(&:strip)
                             .map { |imp| imp.sub(/^(class|struct|enum)\s+([^\.]+)\..*$/, '\2') }

        imports_by_file[File.join("Tests", file)] = imports unless imports.empty?
      end
      
      [imports_by_file.values.flatten, imports_by_file]
    rescue => e
      LOGGER.error("Error processing test imports: #{e.message}")
      [[], {}]
    end
  end

  def store_processed_imports(layer_name, package, target, imports_data, target_import_data, is_test: false)
    imports, imports_by_file = imports_data
    target_name = is_test ? "#{target.name}Tests" : target.name
    
    target_import_data[:processed_imports][layer_name][package.name][target_name] = {
      imports: imports.uniq,
      imports_by_file: imports_by_file,
      mappings: {}
    }
  end

  def process_import_mappings(layer_name, package, target, imports, target_import_data, is_test: false)
    target_name = is_test ? "#{target.name}Tests" : target.name
    
    LOGGER.verbose("Found #{imports.length} total imports (#{imports.uniq.length} unique) in #{target_name}:")
    
    # Get the imports_by_file data for this target
    imports_by_file = target_import_data[:processed_imports][layer_name][package.name][target_name][:imports_by_file]
    
    imports.uniq.each do |import_name|
      mapping = @configuration["TARGET_MAPPINGS"][import_name]
      
      # Check if this is a binary target within the current package
      if !mapping && is_binary_target?(import_name, package.path)
        LOGGER.verbose("  - #{import_name} (BINARY TARGET)")
        # Create a local target mapping for the binary target
        binary_mapping = LocalTarget.new(
          name: import_name,
          package: package
        )
        target_import_data[:processed_imports][layer_name][package.name][target_name][:mappings][import_name] = binary_mapping
      elsif mapping
        LOGGER.verbose("  - #{import_name} (#{mapping})")
        target_import_data[:processed_imports][layer_name][package.name][target_name][:mappings][import_name] = mapping
      else
        LOGGER.verbose("  - #{import_name} (UNMAPPED)")
        # Find files where this import appears
        files = imports_by_file.select { |_, imports| imports.include?(import_name) }.keys
        
        # Initialize array for this import if it doesn't exist
        target_import_data[:unmapped_imports][import_name] ||= []
        # Add the files with their full context
        target_import_data[:unmapped_imports][import_name].concat(
          files.map { |file| "#{layer_name}/#{package.name}/#{target_name}/#{file}" }
        )
      end
    end
    LOGGER.verbose("")
  end

  def is_binary_target?(import_name, package_path)
    frameworks_path = File.join(package_path, "Frameworks")
    return false unless Dir.exist?(frameworks_path)
    
    Dir.entries(frameworks_path)
       .reject { |entry| entry.start_with?('.') }
       .select { |entry| entry.end_with?('.xcframework') }
       .any? { |framework_name| framework_name.sub('.xcframework', '') == import_name }
  end

  def report_unmapped_imports(unmapped_imports)
    if unmapped_imports.any?
      LOGGER.blank_line
      LOGGER.info("Error: Unmapped imports found:")
      unmapped_imports.each do |import_name, files|
        LOGGER.error("#{import_name}")
        files.uniq.each { |file| LOGGER.info("   - Layers/#{file}") }
      end
      LOGGER.blank_line
      LOGGER.info("Please add these to `target_mappings` in `packagebot.yml`")
      exit 1
    end
  end

  def summarize_import_stats(target_import_data)
    total_imports = 0
    unique_imports = Set.new
    total_files = 0
    total_targets = 0
    
    target_import_data[:processed_imports].each do |layer_name, packages|
      packages.each do |package_name, targets|
        targets.each do |target_name, data|
          total_targets += 1
          total_files += data[:imports_by_file].length
          imports = data[:imports_by_file].values.flatten
          total_imports += imports.length
          unique_imports.merge(imports)
        end
      end
    end

    LOGGER.info("Processed #{total_imports} import statements across #{total_files} files in #{total_targets} targets")
  end
end 
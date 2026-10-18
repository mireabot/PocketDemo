require_relative '../logger'
require 'yaml'

class PackageValidator
  include PackageBot
  
  def initialize(configuration)
    @configuration = configuration
  end

  def validate_paths_and_dependencies(target_import_data)
    invalid_paths = find_invalid_paths
    missing_packages = find_missing_package_configs(target_import_data)
    
    report_errors(invalid_paths, missing_packages)
  end

  def validate_target_dependencies(target_import_data, write_violations = false)
    invalid_dependencies = find_invalid_dependencies(target_import_data)
    allowed_violations = read_allowed_violations
    
    if invalid_dependencies.any?
      if write_violations
        write_current_violations(invalid_dependencies)
        LOGGER.success("Updated .packagebot-allowed-violations with current violations")
        return invalid_dependencies
      end
      
      new_violations = find_new_violations(invalid_dependencies, allowed_violations)
      allowed_violations = invalid_dependencies - new_violations
            
      if allowed_violations.any?
        LOGGER.info("Technical Debt - Architectural Violations:")
        allowed_violations.each do |v|
          LOGGER.info("  ⚠️  '#{v[:source_layer]}/#{v[:source]}' -> '#{v[:target_layer]}/#{v[:target]}'")
        end
        LOGGER.info("\nThese violations break our architectural rules and need to be refactored.")
        LOGGER.info("They are temporarily allowed but should be addressed.")
        LOGGER.blank_line
      end
      
      if new_violations.any?
        LOGGER.info("New Violations:")
        new_violations.each do |dep|
          LOGGER.error("'#{dep[:source_layer]}/#{dep[:source]}' -> '#{dep[:target_layer]}/#{dep[:target]}'")
          dep[:files].each { |file| LOGGER.info("    - #{file}") }
        end
        LOGGER.blank_line
        exit 1
      end
    else
      LOGGER.success("No dependency violations found!")
    end
    
    invalid_dependencies
  end

  def read_allowed_violations
    return [] unless File.exist?('.packagebot-allowed-violations')
    
    begin
      yaml = YAML.load_file('.packagebot-allowed-violations')
      yaml['violations'].map do |v|
        {
          source: v['source']['name'],
          target: v['target']['name'],
          source_layer: v['source']['layer'],
          target_layer: v['target']['layer'],
          files: v['files'].sort
        }
      end
    rescue => e
      LOGGER.error("Error reading .packagebot-allowed-violations: #{e.message}")
      []
    end
  end

  private

  def find_invalid_paths
    invalid_paths = []
    
    @configuration["LAYERS"].each do |layer|
      layer.packages.each do |package|
        package.targets.each do |target|
          full_path = "#{package.path}/#{target.relative_path}"
          unless Dir.exist?(full_path)
            invalid_paths << "#{layer.name}/#{package.name}: #{full_path}"
          end
        end
      end
    end
    
    invalid_paths
  end

  def find_missing_package_configs(target_import_data)
    missing_packages = Set.new
    
    @configuration["LAYERS"].each do |layer|
      layer.packages.each do |package|
        package.targets.each do |target|
          target_data = target_import_data[:processed_imports][layer.name][package.name][target.name]
          target_data[:mappings].each do |_, mapping|
            if mapping.is_a?(ThirdPartyTarget)
              unless @configuration["THIRD_PARTY_PACKAGES"][mapping.package_identifier]
                missing_packages.add(mapping.package_identifier)
              end
            end
          end
        end
      end
    end
    
    missing_packages
  end

  def find_invalid_dependencies(target_import_data)
    invalid_dependencies = []
    
    @configuration["LAYERS"].each do |layer|
      layer.packages.each do |package|
        package.targets.each do |target|
          process_target_dependencies(target, layer, target_import_data, invalid_dependencies)
        end
      end
    end
    
    invalid_dependencies
  end

  def process_target_dependencies(target, source_layer, target_import_data, invalid_dependencies)
    target_data = target_import_data[:processed_imports][source_layer.name][target.package.name][target.name]
    
    invalid_imports = {}
    target_data[:imports_by_file].each do |file, imports|
      is_test_file = file.start_with?("Tests/")
      
      imports.each do |import_name|
        mapping = target_data[:mappings][import_name]
        next unless mapping
        next if mapping.is_a?(FirstPartyTarget) || mapping.is_a?(ThirdPartyTarget)
        
        target_layer = find_target_layer(mapping)
        # Allow test files to import their own main target
        next if is_test_file && mapping.name == target.name
        
        if target_layer && !valid_dependency?(source_layer, target_layer, mapping.name)
          LOGGER.verbose("Found invalid dependency: #{target.name} (#{source_layer.name}) -> #{mapping.name} (#{target_layer.name})")
          invalid_imports[mapping.name] ||= []
          invalid_imports[mapping.name] << file
        end
      end
    end
    
    invalid_imports.each do |import_name, files|
      target_layer = find_target_layer(target_data[:mappings][import_name])
      if target_layer
        invalid_dependencies << {
          source: target.name,
          target: import_name,
          source_layer: source_layer.name,
          target_layer: target_layer.name,
          files: files
        }
      else
        LOGGER.verbose("Warning: Could not find target layer for #{import_name}")
      end
    end
  end

  def find_target_layer(mapping)
    @configuration["LAYERS"].find do |layer| 
      layer.packages.any? { |package| package.name == mapping.package_name }
    end
  end

  def valid_dependency?(source_layer, target_layer, target_name)
    source_index = @configuration["LAYERS"].index(source_layer)
    target_index = @configuration["LAYERS"].index(target_layer)
    
    if source_layer == target_layer
      return true if source_layer.allows_intra_layer_dependencies
      
      target_package = target_layer.packages.find { |p| p.targets.any? { |t| t.name == target_name } }
      return true if target_package&.allows_intra_layer_dependencies
    end
    
    target_index > source_index
  end
  
  def report_errors(invalid_paths, missing_packages)
    errors = []
    
    if invalid_paths.any?
      errors << "The following paths do not exist:"
      invalid_paths.each { |path| errors << "  - #{path}" }
    end
    
    if missing_packages.any?
      errors << "\nThe following package configurations are missing from THIRD_PARTY_PACKAGES:"
      missing_packages.each { |package| errors << "  - #{package}" }
    end
    
    if errors.any?
      LOGGER.error(errors.join("\n"))
      exit 1
    end
  end

  def find_new_violations(invalid_dependencies, allowed_violations)
    allowed_map = allowed_violations.map do |v| 
      [violation_key(v), v[:files]]
    end.to_h
    
    # Find new violations and new files in existing violations
    new_violations = []
    invalid_dependencies.each do |dep|
      key = violation_key(dep)
      if allowed_files = allowed_map[key]
        # This is an existing violation - check for new files
        new_files = dep[:files] - allowed_files
        if new_files.any?
          # Create a new violation entry just for the new files
          new_violations << {
            source: dep[:source],
            target: dep[:target],
            source_layer: dep[:source_layer],
            target_layer: dep[:target_layer],
            files: new_files
          }
        end
      else
        # This is a completely new violation
        new_violations << dep
      end
    end
    
    # Find and clean up stale files
    invalid_map = invalid_dependencies.map { |v| [violation_key(v), v[:files]] }.to_h
    cleaned_violations = []
    needs_cleanup = false
    
    allowed_violations.each do |allowed|
      key = violation_key(allowed)
      if current = invalid_map[key]
        # Check for stale files in this violation
        stale_files = allowed[:files] - current
        if stale_files.any?
          needs_cleanup = true
          LOGGER.info("\n🧹 Cleaning up stale files from '#{allowed[:source_layer]}/#{allowed[:source]}' -> '#{allowed[:target_layer]}/#{allowed[:target]}':")
          stale_files.each { |file| LOGGER.info("  - #{file}") }
          # Create cleaned version with only current files
          allowed[:files] = allowed[:files] - stale_files
        end
        cleaned_violations << allowed
      else
        # Entire violation is stale
        needs_cleanup = true
        LOGGER.info("\n🧹 Removing stale violation:")
        LOGGER.info("  '#{allowed[:source_layer]}/#{allowed[:source]}' -> '#{allowed[:target_layer]}/#{allowed[:target]}'")
      end
    end
    
    if needs_cleanup
      write_current_violations(cleaned_violations)
      LOGGER.success("Updated .packagebot-allowed-violations file with cleanup changes")
    end
    
    new_violations
  end

  def write_current_violations(violations)
    yaml = {
      'violations' => violations.map do |v|
        {
          'source' => {
            'name' => v[:source],
            'layer' => v[:source_layer]
          },
          'target' => {
            'name' => v[:target],
            'layer' => v[:target_layer]
          },
          'files' => v[:files].sort
        }
      end
    }
    
    File.write('.packagebot-allowed-violations', YAML.dump(yaml))
  end

  def violation_key(violation)
    "#{violation[:source]}:#{violation[:source_layer]}->#{violation[:target]}:#{violation[:target_layer]}"
  end
end

# Add this helper method to Array class
class Array
  def include_all?(other_array)
    other_array.all? { |elem| self.include?(elem) }
  end
end 
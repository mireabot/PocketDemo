require 'yaml'
require_relative './models/target_mapping'
require_relative './models/package'
require_relative './models/layer'
require_relative './processors/config_loader'
require_relative './processors/package_validator'
require_relative './processors/package_generator'
require_relative './processors/import_processor'
require_relative './logger'

include PackageBot

def main
  write_violations = ARGV.include?('--write-violations')
  skip_validation = ARGV.include?('--skip-validation')
  
  LOGGER.section_header("Loading Configuration")
  config_loader = ConfigLoader.new
  configuration = config_loader.load_configuration
  LOGGER.blank_line
  
  LOGGER.section_header("Processing Imports")
  import_processor = ImportProcessor.new(configuration)
  target_import_data = import_processor.process_target_imports
  LOGGER.blank_line
  
  unless skip_validation
    LOGGER.section_header("Validating Dependencies")
    validator = PackageValidator.new(configuration)
    validator.validate_paths_and_dependencies(target_import_data)
    validator.validate_target_dependencies(target_import_data, write_violations)
    LOGGER.blank_line
  end
  
  LOGGER.section_header("Generating Package Files")
  generator = PackageGenerator.new(configuration)
  generator.generate_package_swift_files(target_import_data)
  LOGGER.blank_line
end

# Main execution
if __FILE__ == $0
  main
end
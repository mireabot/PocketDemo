require 'yaml'
require_relative '../models/target_mapping'
require_relative '../models/package'
require_relative '../models/layer'
require_relative '../logger'

module PackageBot
  class ConfigLoader
    include PackageBot
    class ConfigurationError < StandardError; end
  
    def initialize
      @config = {}
    end
  
    def load_configuration
      begin
        yaml_config = YAML.load_file(File.join(Dir.pwd, 'packagebot.yml'))
        validate_required_keys(yaml_config)
        
        @config = {
          "TARGET_MAPPINGS" => parse_target_mappings(yaml_config["target_mappings"]),
          "THIRD_PARTY_PACKAGES" => parse_third_party_packages(yaml_config["third_party_packages"]),
          "LAYERS" => parse_layers(yaml_config["layers"]),
          "PACKAGE_SETTINGS" => parse_package_settings(yaml_config["package_settings"])
        }
        
        populate_local_target_mappings(@config)
        @config
      rescue ConfigurationError => e
        LOGGER.error("Configuration error: #{e.message}")
        exit 1
      rescue Psych::SyntaxError => e
        LOGGER.error("YAML syntax error: #{e.message}")
        exit 1
      end
    end
  
    private
  
    def populate_local_target_mappings(config)
      config["LAYERS"].each do |layer|
        layer.packages.each do |package|
          package.targets.each do |target|
            config["TARGET_MAPPINGS"][target.name] = LocalTarget.new(
              name: target.name,
              package: package
            )
          end
        end
      end
    end
  
    def validate_required_keys(config)
      unless config["target_mappings"] && config["layers"]
        raise ConfigurationError, "Configuration must include target_mappings and layers"
      end
      
      config["layers"].each do |layer|
        unless layer["name"]
          raise ConfigurationError, "Each layer must have a name"
        end
      end
    end
  
    def parse_target_mappings(mappings)
      result = {}
      
      mappings["first_party"]&.each do |target|
        result[target] = FirstPartyTarget.new(name: target)
      end
      
      mappings["third_party"]&.each do |target|
        result[target["name"]] = ThirdPartyTarget.new(
          name: target["name"],
          package_identifier: target["package_identifier"],
          product_name: target["product_name"]
        )
      end
      
      result
    end
  
    def parse_third_party_packages(packages)
      return {} unless packages

      packages.each_with_object({}) do |(identifier, config), result|
        result[identifier] = config
      end
    end

    def parse_package_settings(settings)
      return {} unless settings

      settings.each_with_object({}) do |(package_name, config), result|
        result[package_name] = config
      end
    end
  
    def parse_layers(layers)
      layers.map do |layer_config|
        LOGGER.info("Processing layer: #{layer_config["name"]}")
        
        unless layer_config["name"]
          raise ConfigurationError, "Layer configuration must include a name"
        end
        
        packages = load_packages_from_filesystem(layer_config["name"], layer_config)
        LOGGER.info("Found #{packages.length} packages in layer #{layer_config["name"]}")
        
        Layer.new(
          name: layer_config["name"],
          packages: packages,
          allows_intra_layer_dependencies: layer_config["allows_intra_layer_dependencies"] || false
        )
      end
    end
  
    def parse_packages(packages)
      packages.map do |package_config|
        unless package_config["name"] && package_config["path"] && package_config["targets"]
          raise ConfigurationError, "Each package must have name, path, and targets"
        end
        
        Package.new(
          name: package_config["name"],
          path: package_config["path"],
          externally_managed: package_config["externally_managed"] || false,
          has_resources: package_config["has_resources"] || false,
          targets: parse_targets(package_config["targets"])
        )
      end
    end
  
    def parse_targets(targets)
      targets.map do |target_config|
        if target_config.is_a?(String)
          PackageTarget.new(
            name: target_config,
            relative_path: "Sources"
          )
        else
          unless target_config["name"] && target_config["relative_path"]
            raise ConfigurationError, "Each target must have name and relative_path"
          end
          
          PackageTarget.new(
            name: target_config["name"],
            relative_path: target_config["relative_path"]
          )
        end
      end
    end

    def load_packages_from_filesystem(layer_name, layer_config)
      base_path = File.join(Dir.pwd, "Layers", layer_name)
      unless Dir.exist?(base_path)
        LOGGER.error("Layer directory not found: #{base_path}")
        return []
      end

      LOGGER.verbose("Loading packages from #{base_path}")
      
      Dir.entries(base_path)
         .reject { |entry| entry.start_with?('.') }
         .map { |package_name| 
           package_path = File.join(base_path, package_name)
           next unless File.directory?(package_path)

           # Check if this is a multi-target package
           multi_target_config = layer_config["multi_target_packages"]&.find { |p| 
             p.is_a?(Hash) ? p["name"] == package_name : p == package_name 
           }
           
           is_multi_target = !multi_target_config.nil?
           allows_intra_layer_dependencies = multi_target_config.is_a?(Hash) ? 
             multi_target_config["allows_intra_layer_dependencies"] || false : false
           
           if is_multi_target
             LOGGER.verbose("Loading multi-target package: #{package_name}")
             targets = load_multi_target_package(package_path)
             if targets.empty?
               LOGGER.error("No targets found in multi-target package: #{package_name}")
             end
           else
             LOGGER.verbose("Loading single-target package: #{package_name}")
             targets = [
               PackageTarget.new(
                 name: package_name,
                 relative_path: "Sources"
               )
             ]
           end

           has_resources = Dir.exist?(File.join(package_path, "Sources", "Resources"))
           LOGGER.verbose("  Resources detected: #{has_resources}")

           Package.new(
             name: package_name,
             path: package_path,
             targets: targets,
             externally_managed: false,
             has_resources: has_resources,
             allows_intra_layer_dependencies: allows_intra_layer_dependencies
           )
         }.compact
    end

    def load_multi_target_package(package_path)
      sources_path = File.join(package_path, "Sources")
      unless Dir.exist?(sources_path)
        LOGGER.error("Sources directory not found in multi-target package: #{package_path}")
        return []
      end

      Dir.entries(sources_path)
         .reject { |entry| entry.start_with?('.') }
         .select { |entry| File.directory?(File.join(sources_path, entry)) }
         .map { |target_name|
           target_path = File.join("Sources", target_name)
           LOGGER.verbose("  Found target: #{target_name} at #{target_path}")
           PackageTarget.new(
             name: target_name,
             relative_path: target_path
           )
         }
    end
  end
end
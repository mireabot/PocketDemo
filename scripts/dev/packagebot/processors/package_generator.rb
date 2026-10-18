require_relative '../logger'
require 'pathname'

class PackageGenerator
  include PackageBot
  
  def initialize(configuration)
    @configuration = configuration
  end

  def generate_package_swift_files(target_import_data)
    generated_count = 0
    layer_counts = {}
    
    @configuration["LAYERS"].each do |layer|
      layer_count = 0
      layer.packages.each do |package|
        next if package.externally_managed
        
        dependencies = find_package_dependencies(package.name, package.targets, target_import_data)
        content = generate_package_swift_content(package.name, package.targets, dependencies, package.path)

        write_package_swift(package.path, content)
        generated_count += 1
        layer_count += 1
      end
      layer_counts[layer.name] = layer_count
    end
    
    # Summary output
    LOGGER.info("Generated Package.swift files:")
    layer_counts.each do |layer_name, count|
      LOGGER.info("  • #{layer_name}: #{count} packages")
    end
    
    format_package_swift_files(generated_count)
  end

  private

  def write_package_swift(package_path, content)
    package_path = "#{package_path}/Package.swift"
    File.write(package_path, content)
    LOGGER.verbose("Generated #{package_path}")
  end
  
  def format_package_swift_files(total_count)
    begin
      package_files = Dir.glob("Layers/**/Package.swift")
      if package_files.any?
        LOGGER.verbose("Running SwiftFormat...")
        system("mint run swiftformat #{package_files.join(' ')} > /dev/null 2>&1")
        
        # Check if any Package.swift files were modified
        git_status = `git diff --name-only -- '**/Package.swift'`.strip
        if git_status.empty?
          LOGGER.blank_line
          LOGGER.success("All Package.swift files are up to date")
        else
          changed_files = git_status.split("\n")
          LOGGER.info("\nModified Package.swift files:")
          changed_files.each { |file| LOGGER.info("  • #{file}") }
        end
      else
        LOGGER.warn("No Package.swift files found to format")
      end
    rescue => e
      LOGGER.error("Failed to run SwiftFormat: #{e.message}")
    end
  end

  def find_package_dependencies(package_name, targets, target_import_data)
    all_dependencies = {}
    target_dependencies = {}
    
    # Process source target dependencies
    targets.each do |target|
      target_deps = Set.new
      
      layer_name = find_layer_name(package_name)
      next unless layer_name
      
      target_data = target_import_data[:processed_imports][layer_name][package_name][target.name]
      process_target_mappings(target, target_data, target_deps, all_dependencies, package_name)
      
      # Process test target dependencies if they exist
      test_target_name = "#{target.name}Tests"
      if target_import_data[:processed_imports][layer_name][package_name][test_target_name]
        test_data = target_import_data[:processed_imports][layer_name][package_name][test_target_name]
        test_data[:mappings].each do |import_name, mapping|
          if mapping.is_a?(ThirdPartyTarget)
            all_dependencies[mapping.package_identifier] = mapping
          elsif mapping.is_a?(LocalTarget) && mapping.package_name != package_name
            all_dependencies[mapping.package_name] = mapping
          end
        end
      end
      
      target_dependencies[target.name] = target_deps
    end
    
    [all_dependencies.values, target_dependencies]
  end

  def find_layer_name(package_name)
    @configuration["LAYERS"].find { |layer| 
      layer.packages.any? { |p| p.name == package_name }
    }&.name
  end

  def process_target_mappings(target, target_data, target_deps, all_dependencies, package_name)
    target_data[:mappings].each do |import_name, mapping|
      next unless mapping
      next if mapping.is_a?(FirstPartyTarget)
      next if target.name == import_name && target.package.name == package_name
      
      if mapping.is_a?(ThirdPartyTarget)
        all_dependencies[mapping.package_identifier] = mapping
        target_deps.add(mapping)
      else
        local_package_name = mapping.package_path
          .split("/").last
          .sub(/^\.\.\//, '')
        
        if local_package_name != package_name
          all_dependencies[local_package_name] = mapping
        end
        
        target_deps.add(mapping)
      end
    end
  end

  def has_tests?(package_path)
    test_path = "#{package_path}/Tests"
    Dir.exist?(test_path) && !Dir.empty?(test_path)
  end

  def generate_package_swift_content(package_name, targets, dependencies_data, current_package_path)
    package_dependencies, target_dependencies = dependencies_data
    
    sorted_deps = sort_dependencies(package_dependencies)
    package_deps = sorted_deps.map { |d| format_package_dependency(d, current_package_path) }.compact
    
    # Detect binary frameworks
    binary_targets = find_binary_targets(current_package_path)
    
    # Sort targets by name before formatting
    sorted_targets = targets.sort_by(&:name)
    formatted_targets = sorted_targets.map do |target|
      target_deps = sort_dependencies(target_dependencies[target.name])
      formatted_target = format_target(target, target_deps)
      formatted_target
    end
    
    # Add test targets in sorted order if Tests directory exists and is not empty
    if has_tests?(current_package_path)
      test_imports = find_test_imports(current_package_path)
      sorted_targets.each do |target|
        formatted_targets << format_test_target(target, test_imports)
      end
    end
    
    generate_swift_package(package_name, sorted_targets, package_deps, formatted_targets)
  end
  
  
  
  def format_test_target(target, test_imports)
    dependencies = [".target(name: \"#{target.name}\")"]
    
    test_imports&.each do |import_name|
      mapping = @configuration["TARGET_MAPPINGS"][import_name]
      case mapping
      when ThirdPartyTarget
        dependencies << ".product(name: \"#{mapping.product_name}\", package: \"#{mapping.package_identifier}\")"
      when LocalTarget
        next if mapping.package_name == target.package.name # Skip if it's the same package
        dependencies << "\"#{mapping.package_name}\""
      end
    end
    
    plugins = []
    if test_imports&.include?("Prefire")
      plugins << ".plugin(name: \"PrefireTestsPlugin\", package: \"Prefire\")"
    end
    
    plugins_section = plugins.any? ? %{,
                  plugins: [
                      #{plugins.join(",\n                    ")}
                  ]} : ""
    
    <<~SWIFT.chomp
      .testTarget(
          name: "#{target.name}Tests",
          dependencies: [
              #{dependencies.uniq.sort.join(",\n            ")}
          ]#{plugins_section}
      )
    SWIFT
  end
  
  def sort_dependencies(dependencies)
    local_deps, third_party_deps = dependencies.partition { |d| d.is_a?(LocalTarget) }
    local_deps.sort_by!(&:name)
    third_party_deps.sort_by!(&:name)
    local_deps + third_party_deps
  end

  def format_package_dependency(dependency, current_package_path)
    case dependency
    when LocalTarget
      from_path = Pathname.new(current_package_path)
      to_path = Pathname.new(dependency.package.path)
      relative_path = to_path.relative_path_from(from_path)
      ".package(path: \"#{relative_path}\")"
    when ThirdPartyTarget
      format_third_party_dependency(dependency)
    end
  end

  def format_third_party_dependency(dependency)
    package_config = @configuration["THIRD_PARTY_PACKAGES"][dependency.package_identifier]
    unless package_config
      LOGGER.error("No package configuration found for #{dependency.package_identifier}")
      LOGGER.error("Please add configuration to THIRD_PARTY_PACKAGES in config.yml")
      exit 1
    end
    
    format_dependency_version(
      package_config["url"],
      package_config["version"],
      package_config["version_rule"],
      dependency.package_identifier
    )
  end

  def format_dependency_version(url, version, version_rule, package_identifier)
    case version_rule
    when "revision"
      ".package(url: \"#{url}\", revision: \"#{version}\")"
    when ".upToNextMajor"
      ".package(url: \"#{url}\", .upToNextMajor(from: \"#{version}\"))"
    when ".upToNextMinor"
      ".package(url: \"#{url}\", .upToNextMinor(from: \"#{version}\"))"
    else
      LOGGER.error("Invalid version rule '#{version_rule}' for package #{package_identifier}")
      LOGGER.error("Valid rules are: 'revision', '.upToNextMajor', '.upToNextMinor'")
      exit 1
    end
  end

  def format_target(target, dependencies)
    sorted_deps = sort_dependencies(dependencies)
    target_dependencies = format_target_dependencies(sorted_deps, target)

    resources_config = target_has_resources?(target) ? ",\n            resources: [.process(\"Resources\")]" : ""
    swift_settings_config = format_swift_settings(target.package.name)

    <<~SWIFT.chomp
      .target(
          name: "#{target.name}",
          dependencies: [
              #{target_dependencies.join(",\n            ")}
          ]#{resources_config}#{swift_settings_config}
      )
    SWIFT
  end

  def format_target_dependencies(dependencies, target)
    dependencies.map do |dep|
      if dep.is_a?(ThirdPartyTarget)
        ".product(name: \"#{dep.product_name}\", package: \"#{dep.package_identifier}\")"
      elsif dep.is_a?(LocalTarget)
        dep.package_name == target.package.name ? "\"#{dep.name}\"" : "\"#{dep.package_name}\""
      else
        "\"#{dep.name}\""
      end
    end.uniq.sort
  end

  def format_swift_settings(package_name)
    package_settings = @configuration["PACKAGE_SETTINGS"]&.[](package_name)
    return "" unless package_settings && package_settings["swift_settings"]

    settings = package_settings["swift_settings"].map do |setting|
      comment = setting["comment"] ? "// #{setting["comment"]}\n                " : ""
      case setting["type"]
      when "unsafeFlags"
        flags_str = setting["flags"].map { |f| "\"#{f}\"" }.join(", ")
        condition = setting["condition"] ? ", #{setting["condition"]}" : ""
        "#{comment}.unsafeFlags([#{flags_str}]#{condition})"
      when "define"
        "#{comment}.define(\"#{setting["value"]}\")"
      else
        LOGGER.warn("Unknown swift_settings type: #{setting["type"]}")
        nil
      end
    end.compact.join(",\n\n                ")

    return "" if settings.empty?

    ",\n            swiftSettings: [\n                #{settings}\n            ]"
  end

  def generate_swift_package(package_name, targets, package_deps, formatted_targets)
    # Check if this package has binary targets
    binary_targets = find_binary_targets(package_name)
    all_target_names = targets.map(&:name) + binary_targets.map { |bt| bt[:name] }
  
    # Construct the full Package.swift content
    <<~SWIFT
      // swift-tools-version: 6.2
      // The swift-tools-version declares the minimum version of Swift required to build this package.
  
      import PackageDescription
  
      let package = Package(
          name: "#{package_name}",
          defaultLocalization: "en",
          platforms: [
              .iOS(.v26),
              .macOS(.v26),
          ],
          products: [
              .library(
                  name: "#{package_name}",
                  targets: [#{all_target_names.map { |t| "\"#{t}\"" }.join(", ")}]
              ),
          ],
          dependencies: [
              #{package_deps.join(",\n              ")}
          ],
          targets: [
              #{formatted_targets.join(",\n              ")}
          ]
      )
    SWIFT
  end
  

  def target_has_resources?(target)
    resources_path = File.join(target.package.path, target.relative_path, 'Resources')
    Dir.glob(File.join(resources_path, '**', '*')).any? { |path| File.file?(path) }
  end

  def find_test_imports(package_path)
    test_path = "#{package_path}/Tests"
    return nil unless Dir.exist?(test_path)
    
    command = "cd #{test_path} && grep -rlE --include='*.swift' '^[[:space:]]*(@[[:alnum:]_]+[[:space:]]+)?((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]' ."
    
    begin
      files = `#{command}`.strip.split("\n").map { |f| f.sub(%r{^\./}, "") }
      imports = Set.new
      
      files.each do |file|
        file_content = File.read(File.join(test_path, file))
        file_imports = file_content.scan(/^[[:space:]]*(?:@\w+[[:space:]]+)?(?:(?:public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+([^\n\/]+)/)
                                 .flatten
                                 .map(&:strip)
                                 .map { |imp| imp.sub(/^(class|struct|enum)\s+([^\.]+)\..*$/, '\2') }
        imports.merge(file_imports)
      end
      
      imports.to_a
    rescue => e
      LOGGER.error("Error processing test imports: #{e.message}")
      []
    end
  end

  def find_binary_targets(package_path)
    frameworks_path = File.join(package_path, "Frameworks")
    return [] unless Dir.exist?(frameworks_path)
    
    Dir.entries(frameworks_path)
       .reject { |entry| entry.start_with?('.') }
       .select { |entry| entry.end_with?('.xcframework') }
       .map { |framework_name|
         target_name = framework_name.sub('.xcframework', '')
         {
           name: target_name,
           path: "Frameworks/#{framework_name}"
         }
       }
  end

  def format_binary_target(binary_target)
    <<~SWIFT.chomp
      .binaryTarget(
          name: "#{binary_target[:name]}",
          path: "#{binary_target[:path]}"
      )
    SWIFT
  end
end 

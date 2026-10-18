require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

generator = File.expand_path('../dev/packagebot/packagebot.rb', __dir__)

def check(condition, message)
  abort "FAIL #{message}" unless condition
  puts "PASS #{message}"
end

Dir.mktmpdir('pocket-package-resources') do |root|
  sources = {}
  %w[ResourceFree Empty Hidden Nested WithResources].each do |name|
    sources[name] = File.join(root, 'Layers', 'Foundation', name, 'Sources')
    FileUtils.mkdir_p(sources[name])
    File.write(File.join(sources[name], 'Fixture.swift'), "public struct Fixture {}\n")
  end
  %w[Empty Hidden Nested WithResources].each do |name|
    FileUtils.mkdir_p(File.join(sources[name], 'Resources'))
  end
  File.write(File.join(sources['Hidden'], 'Resources', '.gitkeep'), '')
  FileUtils.mkdir_p(File.join(sources['Nested'], 'Resources', 'EmptyFolder'))
  FileUtils.mkdir_p(File.join(sources['WithResources'], 'Resources', 'Fixtures'))
  File.write(File.join(sources['WithResources'], 'Resources', 'Fixtures', 'data.json'), '{}')

  %w[First Second].each do |name|
    path = File.join(root, 'Layers', 'Foundation', 'Multi', 'Sources', name)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'Fixture.swift'), "public struct Fixture {}\n")
  end
  multi_resources = File.join(root, 'Layers', 'Foundation', 'Multi', 'Sources', 'First', 'Resources')
  FileUtils.mkdir_p(multi_resources)
  File.write(File.join(multi_resources, 'data.json'), '{}')

  File.write(File.join(root, 'packagebot.yml'), {
    'layers' => [{ 'name' => 'Foundation', 'multi_target_packages' => ['Multi'] }],
    'target_mappings' => {}
  }.to_yaml)
  output, status = Open3.capture2e(RbConfig.ruby, generator, chdir: root)
  check(status.success?, "packagebot generates fixture packages\n#{status.success? ? '' : output}")

  %w[ResourceFree Empty Hidden Nested].each do |name|
    manifest = File.read(File.join(sources[name], '..', 'Package.swift'))
    check(!manifest.include?('resources:'), "#{name} has no resource bundle")
  end
  check(!Dir.exist?(File.join(sources['ResourceFree'], 'Resources')), 'generation does not create an empty Resources folder')
  manifest = File.read(File.join(sources['WithResources'], '..', 'Package.swift'))
  check(manifest.include?('resources: [.process("Resources")]'), 'nested resource files produce a resource bundle')

  manifest = File.read(File.join(root, 'Layers', 'Foundation', 'Multi', 'Package.swift'))
  check(manifest.scan('resources:').length == 1 && manifest.index('resources:') < manifest.index('name: "Second"'),
        'only the named target containing resource files gets a bundle')
end

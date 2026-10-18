class PackageTarget
  attr_accessor :name, :relative_path, :package

  def initialize(name:, relative_path:, package: nil)
    @name = name
    @relative_path = relative_path
    @package = package
  end
end

class Package
  attr_reader :name, :path, :targets, :externally_managed, :has_resources, :allows_intra_layer_dependencies
  
  def initialize(name:, path:, targets:, externally_managed: false, has_resources: false, allows_intra_layer_dependencies: false)
    @name = name
    @path = path
    @targets = targets.map { |t| PackageTarget.new(name: t.name, relative_path: t.relative_path, package: self) }
    @externally_managed = externally_managed
    @has_resources = has_resources
    @allows_intra_layer_dependencies = allows_intra_layer_dependencies
  end
end
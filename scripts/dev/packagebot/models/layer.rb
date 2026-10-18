class Layer
  attr_accessor :name, :packages, :allows_intra_layer_dependencies

  def initialize(name:, packages:, allows_intra_layer_dependencies: false)
    @name = name
    @packages = packages
    @allows_intra_layer_dependencies = allows_intra_layer_dependencies
  end
end 
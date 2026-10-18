# Base class for target mappings
class TargetMapping
  attr_reader :name
  
  def initialize(name)
    @name = name
  end
end

class FirstPartyTarget < TargetMapping
  def to_s
    "First Party (Apple): #{name}"
  end
end

class ThirdPartyTarget < TargetMapping
  attr_reader :package_identifier, :product_name
  
  def initialize(name:, package_identifier:, product_name: nil)
    super(name)
    @package_identifier = package_identifier
    @product_name = product_name || name
  end
  
  def to_s
    "Third Party: #{name} (#{package_identifier})"
  end
end

class LocalTarget < TargetMapping
  attr_reader :name, :package
  
  def initialize(name:, package:)
    super(name)
    @package = package
  end
  
  def package_path
    package.path
  end
  
  def package_name
    package.name
  end
  
  def to_s
    "Local: #{name} (#{package_path})"
  end
end 
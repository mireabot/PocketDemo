require 'pathname'

repo = Pathname.new(File.expand_path('../..', __dir__))
sources = Dir.glob(repo.join('Layers', '*', '*', 'Sources')).select { |path| File.directory?(path) }
violations = []

sources.each do |source|
  groups = Dir.glob(File.join(source, '**', '*.swift')).map { |path| Pathname.new(path) }
              .group_by { |path| path.basename('.swift').to_s.split('+', 2).first }

  groups.each do |name, files|
    next unless files.length > 1 && files.any? { |path| path.basename.to_s.include?('+') }
    next if files.map(&:dirname).uniq.length == 1 && files.first.dirname.basename.to_s == name

    files.sort.each do |path|
      violations << "#{path}: error: Keep #{name}.swift and #{name}+*.swift together in one #{name}/ folder."
    end
  end
end

unless violations.empty?
  warn violations.join("\n")
  exit 1
end

puts 'Swift file groups pass.'

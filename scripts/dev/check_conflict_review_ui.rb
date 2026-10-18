require 'pathname'

repo = Pathname.new(File.expand_path('../..', __dir__))
paths = if ARGV.empty?
          Dir.glob(repo.join('Layers/Features/*/Sources/**/Recording*ConflictView.swift')) +
            [repo.join('Layers/Foundation/PocketUI/Sources/ConflictReviewPrompt/ConflictReviewPrompt.swift').to_s]
        else
          ARGV
        end
violations = []

paths.each do |path|
  source = File.read(path)
  unless source.match?(/\bConflictReviewCard\s*(?:\(|\{)/)
    violations << "#{path}:1: error: Use PocketUI.ConflictReviewCard for the shared conflict stroke and adaptive label color."
  end

  feature_card = File.basename(path).match?(/\ARecording.*ConflictView\.swift(?:\.txt)?\z/)
  source.each_line.with_index(1) do |line, number|
    if feature_card && line.match?(/\bButton\s*(?:\(|\{)|\.(?:buttonStyle|buttonBorderShape|controlSize)\s*\(/)
      violations << "#{path}:#{number}: error: Use PocketUI.ConflictReviewAction; it owns full-width, centered glass buttons with UIColor.label text."
    end
    if line.match?(/\.(?:white|black|blue)\b/)
      violations << "#{path}:#{number}: error: Use PocketPalette.label for conflict text; fixed colors do not adapt to light and dark appearances."
    end
  end
end

unless violations.empty?
  warn violations.join("\n")
  exit 1
end

puts 'Conflict review UI conventions pass.'

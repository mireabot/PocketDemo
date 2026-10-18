require 'open3'
require 'pathname'

repo = Pathname.new(File.expand_path('../..', __dir__))
checker = repo.join('scripts/dev/check_conflict_review_ui.rb').to_s
fixtures = Dir.glob(repo.join('scripts/verification/fixtures/conflict-review/*.swift.txt'))
abort 'Missing captured conflict-review regression fixtures.' unless fixtures.length == 2

fixtures.each do |fixture|
  _, errors, status = Open3.capture3('ruby', checker, fixture)
  unless !status.success? && errors.include?('ConflictReviewCard') && errors.include?('ConflictReviewAction')
    abort "FAIL checker must reject the pre-fix #{File.basename(fixture)} and name both shared components."
  end
  puts "PASS rejects pre-fix #{File.basename(fixture)} with actionable component names"
end

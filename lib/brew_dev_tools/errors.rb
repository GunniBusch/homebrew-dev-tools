# frozen_string_literal: true

module BrewDevTools
  class Error < StandardError; end
  class CommandError < Error; end
  class GitError < Error; end
  class ValidationError < Error; end
  class AmbiguousChangeError < Error; end
end

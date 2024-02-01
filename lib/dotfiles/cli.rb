# frozen_string_literal: true

require "thor"
require "dotfiles"

module Dotfiles
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "setup", "Creates config, templates and output directories, if they don't exist."
    method_option :input, aliases: "-i", type: :string, required: true
    method_option :output, aliases: "-o", type: :string, required: true

    def setup
      Dotfiles.setup(input: options[:input], output: options[:output])
    end
  end
end

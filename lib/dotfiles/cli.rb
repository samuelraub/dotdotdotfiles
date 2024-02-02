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

    desc "compile", "Compiles your ERB templates to the respective out directories."

    def compile
      return unless File.exist? "#{Dir.home}/.dotfiles.yaml"
      df = Dotfiles.new
      df.compile
    end

    desc "link", "Links the compiled files into the home directory."

    def link
      return unless File.exist? "#{Dir.home}/.dotfiles.yaml"
      df = Dotfiles.new
      df.link
    end
  end
end

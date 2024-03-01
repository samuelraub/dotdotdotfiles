# frozen_string_literal: true

require "thor"
require "dotdotdotfiles"

module Dotdotdotfiles
  class CLI < Thor
    def initialize(*args)
      super
      begin
        @df = Dotfiles.new
      rescue Errno::ENOENT
        puts "-- No config file found. Please run `dotdotdotfiles setup` first. --"
      end
    end

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
    method_option :prune, aliases: "-p", type: :boolean, required: false
    method_option :encrypt, aliases: "-e", type: :boolean, required: false

    def compile
      return unless File.exist? "#{Dir.home}/.dotfiles.yaml"
      @df.prune if options[:prune]
      @df.encrypt if options[:encrypt]

      @df.compile
    end

    desc "link", "Links the compiled files into the home directory."

    def link
      return unless File.exist? "#{Dir.home}/.dotfiles.yaml"
      @df.link
    end

    desc "script", "Generates a script that creates symlinks for the desired variants."
    method_option :variants, aliases: "-v", type: :array, required: true

    def script
      return unless File.exist? "#{Dir.home}/.dotfiles.yaml"
      @df.generate_link_script(variant_names: options[:variants])
    end

    desc "encrypt", "Encrypts the secrets defined in the .dotfiles.yaml"

    def encrypt
      return unless File.exist? "#{Dir.home}/.dotfiles.yaml"
      @df.encrypt
    end

  end
end

# frozen_string_literal: true

require "yaml"
require "fileutils"
require "erb"

require_relative "dotfiles/version"

module Dotfiles
  class Error < StandardError; end

  class Dotfiles
    attr_reader :config

    def initialize
      @config = YAML.safe_load(File.read("#{Dir.home}/.dotfiles.yaml"))
    end

    def self.setup(input:, output:)
      if File.exist?("#{Dir.home}/.dotfiles.yaml")
        puts "-- You already have a .dotfiles.yaml --"
        return
      end

      defaults = YAML.safe_load(File.read("#{__dir__}/data/default_config.yaml"))
      defaults["templates_path"] = input
      defaults["output_path"] = output
      custom_config = YAML.dump(defaults)
      File.write("#{Dir.home}/.dotfiles.yaml", custom_config)
      puts "-- Config created --"

      FileUtils.mkdir_p(input)
      FileUtils.mkdir_p(output)
      puts "-- Directories created --"
      true
    end

    def render
      files = @config["files"]
      files.each do |file|
        file["variants"].each do |variant|
          v = { variant.to_sym => true }
          filename = file["name"]
          path = "#{@config["output_path"]}/#{filename}/#{variant}"
          FileUtils.mkdir_p(path)
          template = ERB.new(File.read("#{@config["templates_path"]}/#{filename}.erb"))
          File.write("#{path}/#{filename}",
                     template.result(binding))
        end
      end
    end
  end
end

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

    def setup
      FileUtils.mkdir_p(@config["templates_path"])
      FileUtils.mkdir_p(@config["output_path"])
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

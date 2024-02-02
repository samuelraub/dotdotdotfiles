# frozen_string_literal: true

require "yaml"
require "fileutils"
require "erb"

require_relative "dotdotdotfiles/version"

module Dotdotdotfiles
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

    def link
      files = @config["files"]
      files.each do |file|
        file["variants"].each do |variant|
          next unless variant["links"].is_a? Array

          variant["links"].each do |link|
            FileUtils.rm_rf("#{Dir.home}/#{link}")
            FileUtils.ln_s("#{config["output_path"]}/#{file["name"]}/#{variant["name"]}/#{link}",
                           "#{Dir.home}/#{link}")
          end
        end
      end
    end

    def compile
      files = @config["files"]
      files.each do |file|
        file["variants"].each do |variant|
          variant_name = variant["name"]
          copy_files = variant["copy_files"]
          filename = file["name"]
          path = "#{@config["output_path"]}/#{filename}/#{variant_name}"
          FileUtils.mkdir_p(path)

          if copy_files.is_a? Array
            copy_files.each do |cpf|
              FileUtils.cp_r(cpf, path) unless File.lstat(cpf).symlink?
            end
          end
          v = { variant_name.to_sym => true }
          template = ERB.new(File.read("#{@config["templates_path"]}/#{filename}.erb"))
          File.write("#{path}/#{filename}",
                     template.result(binding))
        end
      end
    end
  end
end

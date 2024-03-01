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
      @config["abs_output_path"] = File.expand_path(@config["output_path"])
      @config["abs_templates_path"] = File.expand_path(@config["templates_path"])
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

      FileUtils.mkdir_p(File.expand_path(input))
      FileUtils.mkdir_p(File.expand_path(output))
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
            FileUtils.ln_s("#{config["abs_output_path"]}/#{file["name"]}/#{variant["name"]}/#{link}",
                           "#{Dir.home}/#{link}")
          end
        end
      end
    end

    def compile
      puts @config["output_path"]
      files = @config["files"]
      files.each do |file|
        file["variants"].each do |variant|
          variant_name = variant["name"]
          copy_files = variant["copy_files"]
          filename = file["name"]
          path = "#{@config["abs_output_path"]}/#{filename}/#{variant_name}"
          FileUtils.mkdir_p(path)

          if copy_files.is_a? Array
            copy_files.each do |cpf|
              FileUtils.cp_r(cpf, path) unless File.lstat(cpf).symlink?
            end
          end
          v = { variant_name.to_sym => true }
          d = self
          template = ERB.new(File.read("#{@config["abs_templates_path"]}/#{filename}.erb"))
          File.write("#{path}/#{filename}",
                     template.result(binding))
        end
      end
    end

    def prune
      FileUtils.rm_rf("#{@config["abs_output_path"]}/.")
    end

    def generate_link_script(variant_names: [])
      script = ""
      files = @config["files"]
      files.each do |file|
        file["variants"].each do |variant|
          next unless variant_names.include? variant["name"]
          script += "rm -rf ~/#{file["name"]}\n"
          script += "ln -s #{@config["output_path"]}/#{file["name"]}/#{variant["name"]}/#{file["name"]} ~/#{file["name"]}\n"
        end
      end
      File.write("#{@config["abs_templates_path"]}/link_#{variant_names.join("_")}.sh", script)
    end

    def encrypt
      files = @config["secrets"]
      return if files.to_a.empty?
      atp = @config["abs_templates_path"]
      files.each do |secret|
        `age -e -i #{atp}/.key.txt -o #{atp}/#{secret}.enc #{atp}/#{secret}`
      end
    end

    def decrypt(file_name)
      atp = @config["abs_templates_path"]
      `age -d -i #{atp}/.key.txt #{atp}/#{file_name}.enc`
    end

  end
end

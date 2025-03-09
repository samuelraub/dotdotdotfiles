# frozen_string_literal: true

require "yaml"
require "fileutils"
require "erb"

require_relative "dotdotdotfiles/version"

module Dotdotdotfiles
  class Error < StandardError; end

  class Dotfiles
    attr_accessor :config

    def initialize
      @config = YAML.safe_load(File.read("#{Dir.home}/.dotfiles.yml"))
      @config["abs_output_path"] = File.expand_path(@config["output_path"])
      @config["abs_templates_path"] = File.expand_path(@config["templates_path"])
    end

    def self.setup(input:, output:)
      if File.exist?("#{Dir.home}/.dotfiles.yml")
        puts "-- You already have a .dotfiles.yml --"
        return
      end

      defaults = YAML.safe_load(File.read("#{__dir__}/data/default_config.yaml"))
      defaults["templates_path"] = input
      defaults["output_path"] = output
      custom_config = YAML.dump(defaults)
      File.write("#{Dir.home}/.dotfiles.yml", custom_config)
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
            puts "#{config["abs_output_path"]}/#{file["name"]}/#{variant["name"]}/#{file["name"]} -> #{Dir.home}/#{link}"
            FileUtils.rm_rf("#{Dir.home}/#{link}")
            FileUtils.ln_s("#{config["abs_output_path"]}/#{file["name"]}/#{variant["name"]}/#{file["name"]}",
                           "#{Dir.home}/#{link}")
          end
        end
      end
    end

    def compile
      files = @config["files"]
      files.each do |file|
        next if file["compile"] == false

        file["variants"].each do |variant|
          variant_name = variant["name"]
          filename = file["name"]
          path = "#{@config["abs_output_path"]}/#{filename}/#{variant_name}"
          FileUtils.mkdir_p(path)

          v = { variant_name.to_sym => true }
          d = self
          template = ERB.new(File.read("#{@config["abs_templates_path"]}/#{filename}.erb"))
          File.write("#{path}/#{filename}",
                     template.result(binding))
        end
      end
      puts "-- Compiled to: #{@config["output_path"]} --"
    end

    def prune
      puts "-- Pruning compiled files from #{@config["abs_output_path"]}/ --"
      dont_compile = @config["files"].filter { |e| e["compile"] == false }
                                     .map { |e| e["name"] }

      Dir.children(@config["abs_output_path"]).each do |entry|
        next if dont_compile.include?(entry)

        FileUtils.rm_rf("#{@config["abs_output_path"]}/#{entry}")
      end
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

# frozen_string_literal: true

require "yaml"
require "fileutils"
require "erb"

require_relative "dotdotdotfiles/version"

module Dotdotdotfiles
  class Error < StandardError; end

  # Finds the manifest: explicit path, then the working directory, then home.
  module Manifest
    NAME = ".dotfiles.yml"
    ENV_VAR = "DOTDOTDOTFILES_CONFIG"

    def self.home
      File.join(Dir.home, NAME)
    end

    def self.explicit(override = nil)
      path = override || ENV[ENV_VAR]
      File.expand_path(path) unless path.to_s.empty?
    end

    def self.candidates(override = nil)
      explicit = explicit(override)
      return [explicit] if explicit

      [File.join(Dir.pwd, NAME), home].uniq
    end

    def self.resolve(override = nil)
      checked = candidates(override)
      checked.find { |path| File.exist?(path) } ||
        raise(Error, "No manifest found. Checked:\n#{checked.map { |path| "  #{path}" }.join("\n")}\n" \
                     "Run `dotdotdotfiles setup`, pass --config or set #{ENV_VAR}.")
    end
  end

  class Dotfiles
    attr_accessor :config
    attr_reader :config_path

    def initialize(config: nil)
      @config_path = Manifest.resolve(config)
      @config = YAML.safe_load(File.read(@config_path))
      @config["abs_output_path"] = File.expand_path(@config["output_path"])
      @config["abs_templates_path"] = File.expand_path(@config["templates_path"])
    end

    def self.setup(input:, output:, config: nil)
      path = Manifest.explicit(config) || Manifest.home
      if File.exist?(path)
        puts "-- You already have a manifest at #{path} --"
        return
      end

      defaults = YAML.safe_load(File.read("#{__dir__}/data/default_config.yaml"))
      defaults["templates_path"] = input
      defaults["output_path"] = output
      custom_config = YAML.dump(defaults)
      File.write(path, custom_config)
      puts "-- Config created at #{path} --"

      FileUtils.mkdir_p(File.expand_path(input))
      FileUtils.mkdir_p(File.expand_path(output))
      puts "-- Directories created --"
      true
    end

    def link
      @config["files"].each do |file|
        file["variants"].each do |variant|
          next unless variant["links"].is_a? Array

          variant["links"].each do |link|
            puts "#{config["abs_output_path"]}/#{file["name"]}/#{variant["name"]}/#{file["name"]} -> #{Dir.home}/#{link}"
            FileUtils.rm_rf("#{Dir.home}/#{link}")
            FileUtils.mkdir_p(File.dirname("#{Dir.home}/#{link}"))
            FileUtils.ln_s("#{config["abs_output_path"]}/#{file["name"]}/#{variant["name"]}/#{file["name"]}",
                           "#{Dir.home}/#{link}")
          end
        end
      end
      link_config
    end

    # Lets later runs find the manifest from any directory.
    def link_config
      home = Manifest.home
      if !File.exist?(home) && !File.symlink?(home)
        puts "#{@config_path} -> #{home}"
        FileUtils.ln_s(@config_path, home)
      elsif !File.exist?(home) || File.realpath(home) != File.realpath(@config_path)
        puts "-- #{home} already exists and is not #{@config_path}; leaving it alone --"
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

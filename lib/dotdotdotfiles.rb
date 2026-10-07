# frozen_string_literal: true

require "yaml"
require "fileutils"
require "erb"
require "open3"

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
      path = [override, ENV[ENV_VAR]].find { |candidate| !candidate.to_s.empty? }
      File.expand_path(path) if path
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

    def self.load(path)
      config = YAML.safe_load(File.read(path), aliases: true)
      unless config.is_a?(Hash) && %w[output_path templates_path].all? { |key| !config[key].to_s.empty? }
        raise Error, "#{path} must set output_path and templates_path."
      end

      config.merge("files" => Array(config["files"]))
    rescue Psych::Exception => e
      raise Error, "#{path} is not valid YAML: #{e.message}"
    end
  end

  # Runs age without a shell, so paths need no quoting and failures are not silent.
  module Age
    def self.run(*args)
      output, error, result = Open3.capture3("age", *args)
      raise Error, "age #{args.join(" ")} failed: #{error.strip}" unless result.success?

      output
    rescue Errno::ENOENT
      raise Error, "age is not installed."
    end
  end

  # Renders, links and encrypts the files listed in the manifest.
  class Dotfiles
    attr_accessor :config
    attr_reader :config_path

    def initialize(config: nil)
      @config_path = Manifest.resolve(config)
      @config = Manifest.load(@config_path)
      @config["abs_output_path"] = File.expand_path(@config["output_path"])
      @config["abs_templates_path"] = File.expand_path(@config["templates_path"])
    end

    def self.setup(input:, output:, config: nil)
      path = Manifest.explicit(config) || Manifest.home
      return puts("-- You already have a manifest at #{path} --") if File.exist?(path)

      defaults = YAML.safe_load(File.read("#{__dir__}/data/default_config.yaml"))
      File.write(path, YAML.dump(defaults.merge("templates_path" => input, "output_path" => output)))
      puts "-- Config created at #{path} --"

      [input, output].each { |dir| FileUtils.mkdir_p(File.expand_path(dir)) }
      puts "-- Directories created --"
      true
    end

    def link
      each_variant do |file, variant|
        next unless variant["links"].is_a? Array

        variant["links"].each { |link| link_file(output_file(file, variant), "#{Dir.home}/#{link}") }
      end
      link_config
    end

    def link_file(source, target)
      # An empty link would resolve to the home directory itself.
      raise Error, "#{source} has an empty link." if File.expand_path(target) == Dir.home
      raise Error, "#{source} does not exist. Run `dotdotdotfiles compile` first." unless File.exist?(source)

      puts "#{source} -> #{target}"
      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.ln_s(source, target)
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

    # Renders everything before touching the output, so a broken template leaves it intact.
    def compile(prune: false)
      rendered = []
      each_variant { |file, variant| rendered << render(file, variant) unless file["compile"] == false }
      self.prune if prune
      rendered.each do |target, content|
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, content)
      end
      puts "-- Compiled to: #{@config["output_path"]} --"
    end

    # Every local in here is visible to the templates.
    def render(file, variant)
      variant_name = variant["name"]
      filename = file["name"]
      path = "#{@config["abs_output_path"]}/#{filename}/#{variant_name}"

      v = { variant_name.to_sym => true }
      d = self
      template = ERB.new(File.read("#{@config["abs_templates_path"]}/#{filename}.erb"))
      ["#{path}/#{filename}", template.result(binding)]
    end

    def prune
      return unless Dir.exist?(@config["abs_output_path"])

      puts "-- Pruning compiled files from #{@config["abs_output_path"]}/ --"
      keep = @config["files"].filter { |e| e["compile"] == false }.map { |e| e["name"] }
      (Dir.children(@config["abs_output_path"]) - keep).each do |entry|
        FileUtils.rm_rf("#{@config["abs_output_path"]}/#{entry}")
      end
    end

    def generate_link_script(variant_names: [])
      script = ""
      each_variant do |file, variant|
        next unless variant_names.include? variant["name"]

        script += "rm -rf ~/#{file["name"]}\n"
        script += "ln -s #{output_file(file, variant, @config["output_path"])} ~/#{file["name"]}\n"
      end
      File.write("#{@config["abs_templates_path"]}/link_#{variant_names.join("_")}.sh", script)
    end

    def encrypt
      atp = @config["abs_templates_path"]
      @config["secrets"].to_a.each do |secret|
        Age.run("-e", "-i", "#{atp}/.key.txt", "-o", "#{atp}/#{secret}.enc", "#{atp}/#{secret}")
      end
    end

    def decrypt(file_name)
      atp = @config["abs_templates_path"]
      Age.run("-d", "-i", "#{atp}/.key.txt", "#{atp}/#{file_name}.enc")
    end

    def each_variant
      @config["files"].each do |file|
        Array(file["variants"]).each { |variant| yield file, variant }
      end
    end

    def output_file(file, variant, root = @config["abs_output_path"])
      "#{root}/#{file["name"]}/#{variant["name"]}/#{file["name"]}"
    end
  end
end

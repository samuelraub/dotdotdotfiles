# frozen_string_literal: true

require "tmpdir"
require "dotdotdotfiles/cli"

RSpec.describe Dotdotdotfiles do
  let(:home) { File.join(@tmp, "home") }
  let(:repo) { File.join(@tmp, "repo") }
  let(:home_manifest) { File.join(home, ".dotfiles.yml") }
  let(:repo_manifest) { File.join(repo, ".dotfiles.yml") }

  around do |example|
    Dir.mktmpdir do |tmp|
      @tmp = File.realpath(tmp)
      [home, repo].each { |dir| FileUtils.mkdir_p(dir) }
      env = ENV.to_h
      ENV["HOME"] = home
      ENV.delete("DOTDOTDOTFILES_CONFIG")
      Dir.chdir(repo) { example.run }
    ensure
      ENV.replace(env)
    end
  end

  before { allow($stdout).to receive(:puts) }

  def write_manifest(path, files: [])
    File.write(path, YAML.dump("templates_path" => repo, "output_path" => "#{repo}/out", "files" => files))
    path
  end

  it "has a version number" do
    expect(Dotdotdotfiles::VERSION).not_to be nil
  end

  describe "manifest lookup" do
    it "falls back to ~/.dotfiles.yml" do
      write_manifest(home_manifest)
      expect(Dotdotdotfiles::Dotfiles.new.config_path).to eq home_manifest
    end

    it "prefers the working directory over home" do
      write_manifest(home_manifest)
      write_manifest(repo_manifest)
      expect(Dotdotdotfiles::Dotfiles.new.config_path).to eq repo_manifest
    end

    it "prefers the env var over the working directory" do
      write_manifest(repo_manifest)
      other = write_manifest(File.join(@tmp, "other.yml"))
      ENV["DOTDOTDOTFILES_CONFIG"] = other
      expect(Dotdotdotfiles::Dotfiles.new.config_path).to eq other
    end

    it "prefers the explicit option over the env var" do
      ENV["DOTDOTDOTFILES_CONFIG"] = write_manifest(repo_manifest)
      other = write_manifest(File.join(@tmp, "other.yml"))
      expect(Dotdotdotfiles::Dotfiles.new(config: other).config_path).to eq other
    end

    it "names the checked paths when nothing is found" do
      expect { Dotdotdotfiles::Dotfiles.new }.to raise_error(Dotdotdotfiles::Error) { |e|
        expect(e.message).to include(repo_manifest, home_manifest)
      }
    end

    it "does not fall back when the override is missing" do
      write_manifest(home_manifest)
      missing = File.join(@tmp, "missing.yml")
      expect { Dotdotdotfiles::Dotfiles.new(config: missing) }
        .to raise_error(Dotdotdotfiles::Error, /#{Regexp.escape(missing)}/)
    end

    it "makes the CLI exit non-zero with the checked paths" do
      expect { Dotdotdotfiles::CLI.start(%w[compile]) }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq 1 }
        .and output(/#{Regexp.escape(repo_manifest)}/).to_stderr
    end
  end

  describe ".setup" do
    it "writes the manifest to home by default" do
      expect(Dotdotdotfiles::Dotfiles.setup(input: "#{repo}/in", output: "#{repo}/out")).to be true
      expect(File).to exist(home_manifest)
      expect(Dir).to exist("#{repo}/in")
    end

    it "writes the manifest to the override" do
      Dotdotdotfiles::Dotfiles.setup(input: repo, output: "#{repo}/out", config: repo_manifest)
      expect(File).to exist(repo_manifest)
      expect(File).not_to exist(home_manifest)
    end
  end

  describe "#compile" do
    it "renders templates per variant" do
      File.write("#{repo}/.rc.erb", "<%= v[:server] ? 'server' : 'default' %>")
      write_manifest(repo_manifest, files: [{ "name" => ".rc", "variants" => [{ "name" => "server" }] }])
      Dotdotdotfiles::Dotfiles.new.compile
      expect(File.read("#{repo}/out/.rc/server/.rc")).to eq "server"
    end
  end

  describe "#link" do
    it "links the files and the manifest into home" do
      write_manifest(repo_manifest,
                     files: [{ "name" => ".rc", "variants" => [{ "name" => "default", "links" => [".rc"] }] }])
      Dotdotdotfiles::Dotfiles.new.link
      expect(File.readlink("#{home}/.rc")).to eq "#{repo}/out/.rc/default/.rc"
      expect(File.readlink(home_manifest)).to eq repo_manifest
    end

    it "keeps a manifest link that already points at the manifest" do
      write_manifest(repo_manifest)
      File.symlink(repo_manifest, home_manifest)
      expect { Dotdotdotfiles::Dotfiles.new.link }.not_to output(/leaving it alone/).to_stdout
      expect(File.readlink(home_manifest)).to eq repo_manifest
    end

    it "leaves a manifest link pointing elsewhere alone" do
      write_manifest(repo_manifest)
      other = write_manifest(File.join(@tmp, "other.yml"))
      File.symlink(other, home_manifest)
      expect { Dotdotdotfiles::Dotfiles.new.link }.to output(/leaving it alone/).to_stdout
      expect(File.readlink(home_manifest)).to eq other
    end

    it "leaves a regular file in home alone" do
      write_manifest(repo_manifest)
      File.write(home_manifest, "mine")
      expect { Dotdotdotfiles::Dotfiles.new.link }.to output(/leaving it alone/).to_stdout
      expect(File.read(home_manifest)).to eq "mine"
    end
  end
end

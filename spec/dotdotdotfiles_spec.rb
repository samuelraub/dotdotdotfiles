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

  def write_manifest(path = repo_manifest, files: [], **extra)
    config = { "templates_path" => repo, "output_path" => "#{repo}/out", "files" => files }
    File.write(path, YAML.dump(config.merge(extra.transform_keys(&:to_s))))
    path
  end

  def entry(name, *variants, **extra)
    { "name" => name, "variants" => variants }.merge(extra.transform_keys(&:to_s))
  end

  def variant(name, *links)
    links.empty? ? { "name" => name } : { "name" => name, "links" => links }
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
      write_manifest
      expect(Dotdotdotfiles::Dotfiles.new.config_path).to eq repo_manifest
    end

    it "prefers the env var over the working directory" do
      write_manifest
      other = write_manifest(File.join(@tmp, "other.yml"))
      ENV["DOTDOTDOTFILES_CONFIG"] = other
      expect(Dotdotdotfiles::Dotfiles.new.config_path).to eq other
    end

    it "prefers the explicit option over the env var" do
      ENV["DOTDOTDOTFILES_CONFIG"] = write_manifest
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

    it "expands ~ in the manifest's paths" do
      write_manifest(templates_path: "~/templates", output_path: "~/out")
      expect(Dotdotdotfiles::Dotfiles.new.config)
        .to include("abs_templates_path" => "#{home}/templates", "abs_output_path" => "#{home}/out")
    end
  end

  describe ".setup" do
    it "writes the manifest to home and creates both directories" do
      expect(Dotdotdotfiles::Dotfiles.setup(input: "#{repo}/in", output: "#{repo}/out")).to be true
      expect(YAML.safe_load(File.read(home_manifest)))
        .to include("templates_path" => "#{repo}/in", "output_path" => "#{repo}/out")
      expect(Dir).to exist("#{repo}/in").and exist("#{repo}/out")
    end

    it "writes the manifest to the override" do
      Dotdotdotfiles::Dotfiles.setup(input: repo, output: "#{repo}/out", config: repo_manifest)
      expect(File).to exist(repo_manifest)
      expect(File).not_to exist(home_manifest)
    end

    it "keeps an existing manifest" do
      File.write(home_manifest, "mine")
      expect(Dotdotdotfiles::Dotfiles.setup(input: "#{repo}/in", output: "#{repo}/out")).to be_nil
      expect(File.read(home_manifest)).to eq "mine"
      expect(Dir).not_to exist("#{repo}/in")
    end
  end

  describe "#compile" do
    it "renders every variant with its own flag" do
      File.write("#{repo}/.rc.erb", "<%= v[:server] ? 'server' : 'other' %>")
      write_manifest(files: [entry(".rc", variant("local"), variant("server"))])
      Dotdotdotfiles::Dotfiles.new.compile
      expect(File.read("#{repo}/out/.rc/local/.rc")).to eq "other"
      expect(File.read("#{repo}/out/.rc/server/.rc")).to eq "server"
    end

    it "skips entries marked compile: false" do
      write_manifest(files: [entry("kitty", variant("default"), compile: false)])
      Dotdotdotfiles::Dotfiles.new.compile
      expect(Dir).not_to exist("#{repo}/out/kitty")
    end
  end

  describe "#prune" do
    it "empties the output directory except for compile: false entries" do
      %w[.rc kitty stale].each { |name| FileUtils.mkdir_p("#{repo}/out/#{name}") }
      write_manifest(files: [entry(".rc", variant("default")), entry("kitty", variant("default"), compile: false)])
      Dotdotdotfiles::Dotfiles.new.prune
      expect(Dir.children("#{repo}/out")).to eq ["kitty"]
    end
  end

  describe "#link" do
    it "links the files and the manifest into home" do
      write_manifest(files: [entry(".rc", variant("default", ".rc"))])
      Dotdotdotfiles::Dotfiles.new.link
      expect(File.readlink("#{home}/.rc")).to eq "#{repo}/out/.rc/default/.rc"
      expect(File.readlink(home_manifest)).to eq repo_manifest
    end

    it "replaces whatever is at the link target" do
      FileUtils.mkdir_p("#{home}/.rc/old")
      write_manifest(files: [entry(".rc", variant("default", ".rc"))])
      Dotdotdotfiles::Dotfiles.new.link
      expect(File.readlink("#{home}/.rc")).to eq "#{repo}/out/.rc/default/.rc"
    end

    it "creates missing parent directories of a link" do
      write_manifest(files: [entry("kitty", variant("default", ".config/kitty"))])
      Dotdotdotfiles::Dotfiles.new.link
      expect(File.readlink("#{home}/.config/kitty")).to eq "#{repo}/out/kitty/default/kitty"
    end

    it "skips variants without links" do
      write_manifest(files: [entry(".rc", variant("server"))])
      Dotdotdotfiles::Dotfiles.new.link
      expect(Dir.children(home)).to eq [".dotfiles.yml"]
    end

    it "keeps a manifest link that already points at the manifest" do
      write_manifest
      File.symlink(repo_manifest, home_manifest)
      expect { Dotdotdotfiles::Dotfiles.new.link }.not_to output(/leaving it alone/).to_stdout
      expect(File.readlink(home_manifest)).to eq repo_manifest
    end

    it "leaves a manifest link pointing elsewhere alone" do
      write_manifest
      other = write_manifest(File.join(@tmp, "other.yml"))
      File.symlink(other, home_manifest)
      expect { Dotdotdotfiles::Dotfiles.new.link }.to output(/leaving it alone/).to_stdout
      expect(File.readlink(home_manifest)).to eq other
    end

    it "leaves a regular file in home alone" do
      write_manifest
      File.write(home_manifest, "mine")
      expect { Dotdotdotfiles::Dotfiles.new.link }.to output(/leaving it alone/).to_stdout
      expect(File.read(home_manifest)).to eq "mine"
    end
  end

  describe "#generate_link_script" do
    it "writes link commands for the requested variants only" do
      write_manifest(files: [entry(".rc", variant("default"), variant("local")), entry(".vimrc", variant("server"))])
      Dotdotdotfiles::Dotfiles.new.generate_link_script(variant_names: %w[default server])
      expect(File.read("#{repo}/link_default_server.sh")).to eq <<~SH
        rm -rf ~/.rc
        ln -s #{repo}/out/.rc/default/.rc ~/.rc
        rm -rf ~/.vimrc
        ln -s #{repo}/out/.vimrc/server/.vimrc ~/.vimrc
      SH
    end
  end

  describe "secrets" do
    before do
      skip "age is not installed" unless system("which age age-keygen > /dev/null 2>&1")
      system("age-keygen -o #{repo}/.key.txt > /dev/null 2>&1")
    end

    it "encrypts the listed secrets and decrypts them for templates" do
      File.write("#{repo}/token", "s3cret")
      File.write("#{repo}/.rc.erb", "token=<%= d.decrypt('token') %>")
      write_manifest(files: [entry(".rc", variant("default"))], secrets: ["token"])
      df = Dotdotdotfiles::Dotfiles.new
      df.encrypt
      expect(File.read("#{repo}/token.enc")).not_to include("s3cret")
      df.compile
      expect(File.read("#{repo}/out/.rc/default/.rc")).to eq "token=s3cret"
    end

    it "does nothing when no secrets are listed" do
      write_manifest
      Dotdotdotfiles::Dotfiles.new.encrypt
      expect(Dir.children(repo)).to contain_exactly(".dotfiles.yml", ".key.txt")
    end
  end

  describe Dotdotdotfiles::CLI do
    let(:df) { instance_double(Dotdotdotfiles::Dotfiles) }

    def stub_dotfiles(config: nil)
      allow(Dotdotdotfiles::Dotfiles).to receive(:new).with(config: config).and_return(df)
    end

    it "exits non-zero with the checked paths when no manifest is found" do
      expect { described_class.start(%w[compile]) }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq 1 }
        .and output(/#{Regexp.escape(repo_manifest)}/).to_stderr
    end

    it "compile only compiles by default" do
      stub_dotfiles
      expect(df).to receive(:compile)
      described_class.start(%w[compile])
    end

    it "compile prunes and encrypts first when asked" do
      stub_dotfiles
      expect(df).to receive(:prune).ordered
      expect(df).to receive(:encrypt).ordered
      expect(df).to receive(:compile).ordered
      described_class.start(%w[compile --prune --encrypt])
    end

    it "passes --config on to the manifest lookup" do
      stub_dotfiles(config: "other.yml")
      expect(df).to receive(:link)
      described_class.start(%w[link --config other.yml])
    end

    it "encrypt encrypts" do
      stub_dotfiles
      expect(df).to receive(:encrypt)
      described_class.start(%w[encrypt])
    end

    it "script passes the variants on" do
      stub_dotfiles
      expect(df).to receive(:generate_link_script).with(variant_names: %w[default server])
      described_class.start(%w[script -v default server])
    end

    it "setup needs no manifest and passes its options on" do
      expect(Dotdotdotfiles::Dotfiles).to receive(:setup).with(input: "in", output: "out", config: "other.yml")
      described_class.start(%w[setup -i in -o out -c other.yml])
    end

    it "setup requires input and output" do
      expect { described_class.start(%w[setup]) }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq 1 }
        .and output(/required options/).to_stderr
    end
  end
end

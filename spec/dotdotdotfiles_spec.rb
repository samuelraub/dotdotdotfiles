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

  def compiled(name, variant_name)
    FileUtils.mkdir_p("#{repo}/out/#{name}/#{variant_name}")
    File.write("#{repo}/out/#{name}/#{variant_name}/#{name}", "")
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

    it "lets the option fall through to the env var when it is empty" do
      ENV["DOTDOTDOTFILES_CONFIG"] = write_manifest(File.join(@tmp, "other.yml"))
      expect(Dotdotdotfiles::Dotfiles.new(config: "").config_path).to eq ENV.fetch("DOTDOTDOTFILES_CONFIG")
    end

    it "rejects a manifest that is not valid YAML" do
      File.write(repo_manifest, "files: [")
      expect { Dotdotdotfiles::Dotfiles.new }.to raise_error(Dotdotdotfiles::Error, /not valid YAML/)
    end

    it "rejects a manifest without its paths" do
      ["", "files: []", "output_path: ''\ntemplates_path: x"].each do |content|
        File.write(repo_manifest, content)
        expect { Dotdotdotfiles::Dotfiles.new }.to raise_error(Dotdotdotfiles::Error, /must set output_path/)
      end
    end

    it "rejects files and variants without a name" do
      bad_names = ["", "/", "..", "a/b", 5].map { |name| [entry(name, variant("default"))] }
      bad_variants = ["", false].map { |name| [entry(".rc", variant(name))] }
      [*bad_names, *bad_variants, [entry(".rc", "default")], [".rc"], { ".rc" => {} }].each do |files|
        write_manifest(files: files)
        expect { Dotdotdotfiles::Dotfiles.new }.to raise_error(Dotdotdotfiles::Error, /needs a name/)
      end
    end

    it "accepts YAML aliases, a missing files list and entries without variants" do
      File.write(repo_manifest, "output_path: &dir #{repo}\ntemplates_path: *dir\n")
      expect { Dotdotdotfiles::Dotfiles.new.compile }.not_to raise_error
      write_manifest(files: [{ "name" => ".rc" }])
      expect { Dotdotdotfiles::Dotfiles.new.compile }.not_to raise_error
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

    it "writes a manifest that loads and documents the entries" do
      Dotdotdotfiles::Dotfiles.setup(input: repo, output: "#{repo}/out")
      df = Dotdotdotfiles::Dotfiles.new
      expect(df.config).to include("files" => [], "secrets" => [])
      expect { [df.encrypt, df.compile(prune: true), df.link] }.not_to raise_error
      expect(File.read(home_manifest)).to include("# files:")
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

    it "leaves the output untouched when a template fails, even when pruning" do
      FileUtils.mkdir_p("#{repo}/out/.a/default")
      File.write("#{repo}/out/.a/default/.a", "old")
      File.write("#{repo}/.a.erb", "new")
      File.write("#{repo}/.b.erb", "<%= raise 'broken' %>")
      write_manifest(files: [entry(".a", variant("default")), entry(".b", variant("default"))])
      expect { Dotdotdotfiles::Dotfiles.new.compile(prune: true) }.to raise_error("broken")
      expect(File.read("#{repo}/out/.a/default/.a")).to eq "old"
    end

    it "prunes stale output when asked" do
      FileUtils.mkdir_p("#{repo}/out/stale")
      File.write("#{repo}/.rc.erb", "rc")
      write_manifest(files: [entry(".rc", variant("default"))])
      Dotdotdotfiles::Dotfiles.new.compile(prune: true)
      expect(Dir.children("#{repo}/out")).to eq [".rc"]
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

    it "does nothing when the output directory does not exist yet" do
      write_manifest
      expect { Dotdotdotfiles::Dotfiles.new.prune }.not_to raise_error
    end
  end

  describe "#link" do
    it "links the files and the manifest into home" do
      compiled(".rc", "default")
      write_manifest(files: [entry(".rc", variant("default", ".rc"))])
      Dotdotdotfiles::Dotfiles.new.link
      expect(File.readlink("#{home}/.rc")).to eq "#{repo}/out/.rc/default/.rc"
      expect(File.readlink(home_manifest)).to eq repo_manifest
    end

    it "replaces whatever is at the link target" do
      FileUtils.mkdir_p("#{home}/.rc/old")
      compiled(".rc", "default")
      write_manifest(files: [entry(".rc", variant("default", ".rc"))])
      Dotdotdotfiles::Dotfiles.new.link
      expect(File.readlink("#{home}/.rc")).to eq "#{repo}/out/.rc/default/.rc"
    end

    it "creates missing parent directories of a link" do
      compiled("kitty", "default")
      write_manifest(files: [entry("kitty", variant("default", ".config/kitty"))])
      Dotdotdotfiles::Dotfiles.new.link
      expect(File.readlink("#{home}/.config/kitty")).to eq "#{repo}/out/kitty/default/kitty"
    end

    it "keeps the target when the source has not been compiled" do
      File.write("#{home}/.rc", "mine")
      write_manifest(files: [entry(".rc", variant("default", ".rc"))])
      expect { Dotdotdotfiles::Dotfiles.new.link }.to raise_error(Dotdotdotfiles::Error, /compile/)
      expect(File.read("#{home}/.rc")).to eq "mine"
    end

    it "refuses a link that is not inside the home directory" do
      compiled(".rc", "default")
      File.write("#{@tmp}/precious", "mine")
      ["", ".", nil, "..", "x/../..", "../precious", "#{@tmp}/precious"].each do |link|
        write_manifest(files: [entry(".rc", variant("default", link))])
        expect { Dotdotdotfiles::Dotfiles.new.link }.to raise_error(Dotdotdotfiles::Error, /not inside/)
      end
      expect(File.read("#{@tmp}/precious")).to eq "mine"
    end

    it "refuses the home directory itself when HOME ends in a slash" do
      compiled(".rc", "default")
      write_manifest(files: [entry(".rc", variant("default", ""))])
      ENV["HOME"] = "#{home}/"
      expect { Dotdotdotfiles::Dotfiles.new.link }.to raise_error(Dotdotdotfiles::Error, /not inside/)
      expect(Dir).to exist(home)
    end

    it "replaces nothing when a later link is invalid" do
      compiled(".a", "default")
      File.write("#{home}/.a", "mine")
      write_manifest(files: [entry(".a", variant("default", ".a")), entry(".b", variant("default", ".b"))])
      expect { Dotdotdotfiles::Dotfiles.new.link }.to raise_error(Dotdotdotfiles::Error, /compile/)
      expect(File.read("#{home}/.a")).to eq "mine"
    end

    it "refuses two links to the same target" do
      [".a", ".b"].each { |name| compiled(name, "default") }
      File.write("#{home}/.rc", "mine")
      write_manifest(files: [entry(".a", variant("default", ".rc")), entry(".b", variant("default", "x/../.rc"))])
      expect { Dotdotdotfiles::Dotfiles.new.link }.to raise_error(Dotdotdotfiles::Error, /more than once/)
      expect(File.read("#{home}/.rc")).to eq "mine"
    end

    it "refuses a link that would replace its own source" do
      FileUtils.mkdir_p("#{home}/dotfiles/out/.rc/default")
      File.write("#{home}/dotfiles/out/.rc/default/.rc", "")
      write_manifest(output_path: "#{home}/dotfiles/out", files: [entry(".rc", variant("default", "dotfiles"))])
      expect { Dotdotdotfiles::Dotfiles.new.link }.to raise_error(Dotdotdotfiles::Error, /its own source/)
      expect(File).to exist("#{home}/dotfiles/out/.rc/default/.rc")
    end

    it "fails when the target cannot be removed" do
      compiled(".rc", "default")
      FileUtils.mkdir_p("#{home}/.rc/locked")
      File.write("#{home}/.rc/locked/file", "")
      File.chmod(0o500, "#{home}/.rc/locked")
      write_manifest(files: [entry(".rc", variant("default", ".rc"))])
      expect { Dotdotdotfiles::Dotfiles.new.link }.to raise_error(SystemCallError)
      expect(File).not_to be_symlink("#{home}/.rc/.rc")
    ensure
      File.chmod(0o700, "#{home}/.rc/locked")
    end

    it "accepts a single link given as a string" do
      compiled(".rc", "default")
      write_manifest(files: [{ "name" => ".rc", "variants" => [{ "name" => "default", "links" => ".rc" }] }])
      Dotdotdotfiles::Dotfiles.new.link
      expect(File).to be_symlink("#{home}/.rc")
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

    it "quotes names for the shell" do
      write_manifest(files: [entry("my rc", variant("default"))])
      Dotdotdotfiles::Dotfiles.new.generate_link_script(variant_names: %w[default])
      expect(File.read("#{repo}/link_default.sh")).to eq <<~SH
        rm -rf ~/my\\ rc
        ln -s #{repo}/out/my\\ rc/default/my\\ rc ~/my\\ rc
      SH
    end
  end

  describe "secrets" do
    def generate_key
      skip "age is not installed" unless system("which age age-keygen > /dev/null 2>&1")
      system("age-keygen -o #{repo}/.key.txt > /dev/null 2>&1")
    end

    it "encrypts the listed secrets and decrypts them for templates" do
      generate_key
      File.write("#{repo}/token", "s3cret")
      File.write("#{repo}/.rc.erb", "token=<%= d.decrypt('token') %>")
      write_manifest(files: [entry(".rc", variant("default"))], secrets: ["token"])
      df = Dotdotdotfiles::Dotfiles.new
      df.encrypt
      expect(File.read("#{repo}/token.enc")).not_to include("s3cret")
      df.compile
      expect(File.read("#{repo}/out/.rc/default/.rc")).to eq "token=s3cret"
    end

    it "fails instead of rendering an empty secret" do
      generate_key
      File.write("#{repo}/.rc.erb", "token=<%= d.decrypt('missing') %>")
      write_manifest(files: [entry(".rc", variant("default"))], secrets: ["missing"])
      df = Dotdotdotfiles::Dotfiles.new
      expect { df.encrypt }.to raise_error(Dotdotdotfiles::Error, /age .* failed/)
      expect { df.compile }.to raise_error(Dotdotdotfiles::Error, /age .* failed/)
      expect(Dir).not_to exist("#{repo}/out")
    end

    it "accepts a single secret given as a string" do
      generate_key
      File.write("#{repo}/token", "s3cret")
      write_manifest(secrets: "token")
      Dotdotdotfiles::Dotfiles.new.encrypt
      expect(File).to exist("#{repo}/token.enc")
    end

    it "handles paths with spaces" do
      generate_key
      File.write("#{repo}/my token", "s3cret")
      write_manifest(secrets: ["my token"])
      df = Dotdotdotfiles::Dotfiles.new
      df.encrypt
      expect(df.decrypt("my token")).to eq "s3cret"
    end

    it "says so when age is not installed" do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)
      write_manifest
      expect { Dotdotdotfiles::Dotfiles.new.decrypt("token") }
        .to raise_error(Dotdotdotfiles::Error, "age is not installed.")
    end

    it "does nothing when no secrets are listed" do
      write_manifest
      Dotdotdotfiles::Dotfiles.new.encrypt
      expect(Dir.children(repo)).to eq [".dotfiles.yml"]
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

    it "reports a missing template without a backtrace" do
      write_manifest(files: [entry(".rc", variant("default"))])
      expect { described_class.start(%w[compile]) }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq 1 }
        .and output(/No such file.*\.rc\.erb/).to_stderr
    end

    it "turns any library error into a message and exit status 1" do
      File.write(repo_manifest, "files: [")
      expect { described_class.start(%w[link]) }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq 1 }
        .and output(/not valid YAML/).to_stderr
    end

    it "compile only compiles by default" do
      stub_dotfiles
      expect(df).to receive(:compile).with(prune: false)
      described_class.start(%w[compile])
    end

    it "compile encrypts first and passes --prune on" do
      stub_dotfiles
      expect(df).to receive(:encrypt).ordered
      expect(df).to receive(:compile).with(prune: true).ordered
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

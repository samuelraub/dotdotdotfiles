# frozen_string_literal: true

RSpec.describe Dotdotdotfiles do
  it "has a version number" do
    expect(Dotdotdotfiles::VERSION).not_to be nil
  end

  it "loads the default config" do
    df = Dotdotdotfiles::Dotfiles.new
    expect(df.config).not_to be_empty
  end

  it "creates tempate and output directories" do
    df = Dotdotdotfiles::Dotfiles.new
    expect(df.setup).to be true
  end

  it "renders templates" do
    df = Dotdotdotfiles::Dotfiles.new
    expect(df.compile).not_to be 0
  end
end

# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

namespace :dev do
  task :setup do
    ruby "-I lib exe/dotfiles setup"
  end
end

task default: %i[spec rubocop]

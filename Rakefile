# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

namespace :dev do
  task :setup do
    ruby "-I lib exe/dotdotdotfiles setup"
  end
  task :compile do
    ruby "-I lib exe/dotdotdotfiles compile"
  end
  task :link do
    ruby "-I lib exe/dotdotdotfiles link"
  end
end

task default: %i[spec rubocop]

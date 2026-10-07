# Dotdotdotfiles

TODO: Delete this and the text below, and describe your gem

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/dotdotdotfiles`. To experiment with that code, run `bin/console` for an interactive prompt.

## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_PRIOR_TO_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

    $ bundle add UPDATE_WITH_YOUR_GEM_NAME_PRIOR_TO_RELEASE_TO_RUBYGEMS_ORG

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install UPDATE_WITH_YOUR_GEM_NAME_PRIOR_TO_RELEASE_TO_RUBYGEMS_ORG

## Usage

### Manifest location

Every command reads its manifest from the first of these that applies:

1. `--config PATH` (`-c`), or the `DOTDOTDOTFILES_CONFIG` environment variable. An explicit path that does not exist
   is an error; there is no fallback.
2. `.dotfiles.yml` in the current working directory
3. `~/.dotfiles.yml`

If none is found, the command lists the paths it checked and exits non-zero.

Relative `templates_path` and `output_path` values are resolved against the directory the manifest lives in, so
`templates_path: .` and `output_path: out` work wherever the repository is cloned.

`dotdotdotfiles link` also symlinks `~/.dotfiles.yml` to the manifest it used, so later runs work from any directory.
An existing `~/.dotfiles.yml` that is a different file is reported and left untouched.

`dotdotdotfiles setup -i TEMPLATES -o OUTPUT` writes a new manifest to `~/.dotfiles.yml`, or to the explicit path
from 1.

On a new machine, with the manifest kept in the dotfiles repository:

    $ cd ~/dotfiles
    $ dotdotdotfiles compile && dotdotdotfiles link

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/dotdotdotfiles.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

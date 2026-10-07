# Dotdotdotfiles

Keeps dotfiles as ERB templates in one directory, renders them into an output
directory per variant (say `default`, `local`, `server`), and symlinks the
rendered files into `$HOME`. A manifest, `.dotfiles.yml`, lists the files, their
variants and where each one is linked. Secrets can be kept encrypted with
[age](https://age-encryption.org) next to the templates.

```
dotdotdotfiles setup -i ~/dotfiles -o ~/dotfiles/out   # manifest and directories
dotdotdotfiles compile [--prune] [--encrypt]           # render the templates
dotdotdotfiles link                                    # symlink into $HOME
dotdotdotfiles script -v default server                # a shell script that links those variants
dotdotdotfiles encrypt                                 # encrypt the secrets named in the manifest
```

`dotdotdotfiles help` lists the commands and their options.

`link` replaces what is at a link's place, and `compile --prune` deletes from
the output directory what the manifest no longer names. `link` checks every
link before it replaces anything, and `compile` renders every template before
it writes or prunes.

## Installation

The gem is not on rubygems.org; releases are tags of this repository.

In a Gemfile:

```ruby
gem "dotdotdotfiles", github: "samuelraub/dotdotdotfiles", tag: "v0.2.0"
```

As a command on your machine:

```sh
git clone https://github.com/samuelraub/dotdotdotfiles && cd dotdotdotfiles
git checkout <tag>
bin/setup && bundle exec rake install
```

Working with secrets needs the `age` command.

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

`bin/setup` installs the dependencies; `bundle exec rake` runs the specs and
RuboCop, which is what CI runs. The specs use a temporary directory as `HOME`.
Running the command from a checkout against your real home directory replaces
real files; try things out with `HOME=<some empty directory>`.

Releases are described in `CLAUDE.md`.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

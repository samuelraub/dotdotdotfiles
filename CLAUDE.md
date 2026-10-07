# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Ruby gem (Thor CLI) that renders dotfiles from ERB templates into per-variant output directories and symlinks them into `$HOME`. Apart from the manifest-location section, `README.md` is still `bundle gem` boilerplate — the code is the documentation.

## Commands

```sh
bin/setup                                  # bundle install
bundle exec rake                           # default: spec + rubocop (what CI runs)
bundle exec rspec -e "manifest lookup"     # examples matching a description
bundle exec rubocop -a                     # lint, autocorrect
bundle exec rake install                   # build into pkg/ and install the gem locally
ruby -I lib exe/dotdotdotfiles <command>   # run the CLI from source without installing
```

`rake dev:compile` and `rake dev:link` wrap the last form (`compile -p` and `link`).

## Releasing

The gem is not on rubygems.org; a release is a git tag with a GitHub release. Two steps, because `main` only changes through pull requests:

1. A pull request that makes `main` say the new version: `VERSION` in `lib/dotdotdotfiles/version.rb` (and with it `Gemfile.lock`), the entries under `[Unreleased]` in `CHANGELOG.md` moved under a `## [x.y.z] - date` heading (leaving `[Unreleased]` empty), and the `tag:` line in the README.
2. The `Release` workflow (`workflow_dispatch` on `main`). It checks those against each other and against the existing tags, runs CI, then creates the tag `vx.y.z` and a GitHub release with that changelog section as notes. It commits nothing; `dry_run` only checks.

So every change a user will notice needs a line under `[Unreleased]` when it is made. Do not use `rake release`: it would tag and push by itself, and the gemspec refuses the push to rubygems.org.

## Manifest lookup and the real home directory

`Dotdotdotfiles::Manifest` is the only place that knows where the manifest is: `--config` / `DOTDOTDOTFILES_CONFIG`, then `./.dotfiles.yml`, then `~/.dotfiles.yml`. `Manifest.load` validates it. Expected failures raise `Dotdotdotfiles::Error`; `CLI.start` turns those and `SystemCallError` (e.g. a missing template) into a message on stderr and exit 1.

- The specs run with a temp dir as `HOME` and as cwd (the `around` hook in `spec/dotdotdotfiles_spec.rb`); keep new examples inside it, since link targets are always resolved against `Dir.home`.
- **`rake dev:*` and `ruby -I lib exe/dotdotdotfiles ...` are destructive on this machine**: `link` removes every link target before symlinking, and `compile -p` deletes everything in the output directory except `compile: false` entries. Try things out with `HOME=<tmpdir>`.

## Architecture

Two files carry all the logic:

- `lib/dotdotdotfiles.rb` — `Dotdotdotfiles::Manifest` (lookup, see above) and `Dotdotdotfiles::Dotfiles`, which holds the parsed config and implements `setup`, `compile`, `prune`, `link`, `generate_link_script`, `encrypt`, `decrypt`.
- `lib/dotdotdotfiles/cli.rb` — `Dotdotdotfiles::CLI < Thor`, a thin mapping of subcommands onto those methods. `Dotfiles` is built lazily through the `df` helper, so `setup` works without a manifest.

### Config shape (`.dotfiles.yml`)

`setup` writes `lib/data/default_config.yaml` (empty `files`/`secrets`) followed by the commented example in `lib/data/example.yaml`. `Manifest.load` requires both paths, and file and variant names that are single path segments. The shape:

```yaml
templates_path: ~/dotfiles        # where <name>.erb, secrets and .key.txt live
output_path: ~/dotfiles/out
files:
  - name: .zshrc
    compile: false                # optional; skip rendering and pruning
    variants:
      - name: default
        links:                    # paths relative to $HOME
          - .zshrc
secrets:
  - some_secret_file
```

`abs_templates_path` / `abs_output_path` are derived at load time by `Manifest.expand`: relative paths count from the real manifest's directory (through the `~/.dotfiles.yml` symlink), never from the working directory.

### Path convention

The rendered artefact for a file/variant pair is always:

```
<output_path>/<file name>/<variant name>/<file name>
```

`link` and `generate_link_script` get it from `output_file`; `render` builds the same directory itself because `path` is a template local — change the layout in both.

### Template rendering

`compile` calls `render` once per variant, which reads `<templates_path>/<name>.erb` and evaluates it with its own `binding`. Everything is rendered in memory before anything is pruned or written. Templates see these locals:

- `v` — `{ <variant_name>: true }`, for branching: `<% if v[:server] %>`
- `d` — the `Dotfiles` instance, mainly for `<%= d.decrypt("some_secret_file") %>`
- also `file`, `variant`, `filename`, `variant_name`, `path`

Renaming locals inside `render` is therefore a breaking change for users' templates.

### Secrets

`encrypt` and `decrypt` run `age` through `Age.run` (no shell; a non-zero exit raises), using `<templates_path>/.key.txt` as the identity. Each name under `secrets` is encrypted to `<templates_path>/<name>.enc`; `decrypt(name)` returns the plaintext for use inside templates. `compile -e` re-encrypts before rendering.

### `link` vs `script`

`link` honours each variant's `links` array (and skips variants without one), then symlinks `~/.dotfiles.yml` to the manifest in use unless something else is already there. `Links.check` validates every link (inside home, no overlapping targets, clear of the output and templates directories, source exists) before any target is replaced. It and `prune` compare resolved paths via `Paths`, never the spelled ones. `script -v a b` writes `<templates_path>/link_a_b.sh` for use on another machine, but ignores `links` and always targets `~/<file name>`, using `output_path` as written (a relative one is rewritten as seen from `~`).

## Conventions

- RuboCop: double-quoted strings, 120-column lines, `TargetRubyVersion: 2.6`.
- `.ruby-version` and CI both use 3.3.4; the gemspec allows `>= 2.6.0`, which is also rubocop's target.
- Commit messages follow `type(scope): subject`, e.g. `fix(CLI): don't prune non-compiled files`.
- `sig/dotfiles.rbs` is a stale stub from the gem's former name (`dotfiles`).

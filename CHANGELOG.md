## [Unreleased]

## [0.2.0] - 2026-10-07

- Requires Ruby 3.3 or newer. The gemspec used to allow 2.6, which was never tested
- Look up the manifest via `--config` / `DOTDOTDOTFILES_CONFIG`, then `./.dotfiles.yml`, then `~/.dotfiles.yml`
- Exit non-zero and list the checked paths when no manifest is found, instead of returning silently
- `link` symlinks `~/.dotfiles.yml` to the manifest in use, without replacing an existing one
- `setup` writes the manifest to the explicit path when one is given
- `link` creates missing parent directories of a link target (e.g. `~/.config`) instead of failing
- Allow thor 1.x from 1.3 on
- Relative `output_path` and `templates_path` are resolved against the manifest's directory instead of the working
  directory, and `setup` stores relative `-i`/`-o` arguments as absolute paths
- Remove the `dev:setup` rake task, which could not pass the required options
- `link` refuses a link that does not resolve to a path inside the home directory (an empty one used to delete it)
- `link` checks every link and source first, and replaces nothing when one of them is invalid
- `link` refuses links that overlap (the same target twice, or one inside another) and links that would replace
  anything in the output or templates directories; symlinks in the paths are resolved before comparing
- Links must be strings
- `compile --prune` refuses an output directory that holds the templates
- `setup` creates the directories before the manifest, so `--config` may point into them
- `link` fails when an existing target cannot be removed, instead of linking into it
- `links` and `secrets` may be a single string instead of a list
- File and variant names must be non-empty strings without `/`
- `setup` writes a manifest with empty `files` and `secrets` plus a commented example, so it loads as written
- `script` quotes file names for the shell
- `compile` renders every template before it writes or prunes, so a failing template leaves the output as it was
- `compile --prune` no longer fails when the output directory does not exist yet
- A failing `age` call aborts with its error instead of rendering an empty secret; paths with spaces work
- Manifest problems (invalid YAML, missing `output_path`/`templates_path`, invalid file or variant names) and
  file system errors such as a missing template are reported as a message with exit status 1 instead of a
  backtrace; YAML aliases are accepted

## [0.1.0] - 2024-02-01

- Initial release

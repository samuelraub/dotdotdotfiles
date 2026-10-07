## [Unreleased]

- Look up the manifest via `--config` / `DOTDOTDOTFILES_CONFIG`, then `./.dotfiles.yml`, then `~/.dotfiles.yml`
- Exit non-zero and list the checked paths when no manifest is found, instead of returning silently
- `link` symlinks `~/.dotfiles.yml` to the manifest in use, without replacing an existing one
- `setup` writes the manifest to the explicit path when one is given
- `link` creates missing parent directories of a link target (e.g. `~/.config`) instead of failing
- Allow thor 1.x from 1.3 on
- `link` refuses a link that is empty or resolves to the home directory itself, which it used to delete
- `link` stops before replacing a target whose source has not been compiled
- `compile` renders every template before it writes or prunes, so a failing template leaves the output as it was
- `compile --prune` no longer fails when the output directory does not exist yet
- A failing `age` call aborts with its error instead of rendering an empty secret; paths with spaces work
- Manifest problems (invalid YAML, missing `output_path`/`templates_path`) are reported as a message with exit
  status 1 instead of a backtrace; YAML aliases are accepted

## [0.1.0] - 2024-02-01

- Initial release

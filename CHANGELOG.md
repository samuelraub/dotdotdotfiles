## [Unreleased]

- Look up the manifest via `--config` / `DOTDOTDOTFILES_CONFIG`, then `./.dotfiles.yml`, then `~/.dotfiles.yml`
- Exit non-zero and list the checked paths when no manifest is found, instead of returning silently
- `link` symlinks `~/.dotfiles.yml` to the manifest in use, without replacing an existing one
- `setup` writes the manifest to the explicit path when one is given

## [0.1.0] - 2024-02-01

- Initial release

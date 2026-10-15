# botmux-bin (Arch / Manjaro package)

PKGBUILD for [botmux](https://github.com/deepcoldy/botmux) that repackages the
official self-contained release binary (`botmux-linux-x64` / `botmux-linux-arm64`,
glibc builds) from GitHub Releases. Nothing is compiled; nothing is written to `$HOME`.

- Installs `/usr/bin/botmux` and the MIT license.
- Depends on `tmux` (and `glibc`). You also need at least one AI coding CLI
  (optdepends: `claude-code`, `openai-codex`, `cursor-cli`; adjust names to whatever
  provides those CLIs on your system).
- Conflicts with / provides `botmux`.

## Build and install locally (Manjaro / Arch)

```bash
sudo pacman -S --needed base-devel tmux
cd botmux-bin
makepkg -si
botmux --version
botmux setup        # run as your normal user; config lives in ~/.botmux
```

(`makepkg` downloads ~180 MB and verifies SHA-256 sums.)

> **Don't use `botmux upgrade` or the upstream `install.sh`** with this package. They
> install a second copy in `~/.botmux/bin/botmux` and append PATH lines to your shell
> startup files, which then shadows the pacman-managed `/usr/bin/botmux`. Upgrade by
> rebuilding/updating the package, then run `botmux restart`.

## Automatic updates via GitHub Actions

`.github/workflows/update-aur.yml` runs every 6 hours (and on manual dispatch). It runs
`scripts/update-pkg.sh`, which:

1. reads the latest upstream release tag,
2. compares it with `pkgver` in `PKGBUILD`,
3. if newer: sets `pkgver`, resets `pkgrel=1`, downloads each arch's binary, computes
   SHA-256 (cross-checked against the release's `.sha256` file) and rewrites the sums,
4. regenerates `.SRCINFO`,
5. commits and pushes `PKGBUILD` + `.SRCINFO`,
6. publishes to the AUR with
   [KSXGitHub/github-actions-deploy-aur](https://github.com/KSXGitHub/github-actions-deploy-aur)
   **only if** the `AUR_SSH_PRIVATE_KEY` secret exists.

You can also run the helper by hand: `scripts/update-pkg.sh --check` (report only),
`scripts/update-pkg.sh` (update), `--force`, `--version X.Y.Z`, `--srcinfo-only`.

### Put it in your own GitHub repo

```bash
cd botmux-bin
git init -b main
git add .
git commit -m "Initial botmux-bin package"
gh repo create botmux-bin --public --source . --push     # or add a remote manually
```

In the repo: Settings -> Actions -> General -> Workflow permissions -> **Read and write**
(the workflow also declares `contents: write`). Edit the `# Maintainer:` line in `PKGBUILD`.

### Publish to the AUR (optional)

1. Create an AUR account and add an SSH public key to it (AUR -> My Account).
2. Generate a dedicated key: `ssh-keygen -t ed25519 -f aur_key -C "botmux-bin CI" -N ""`
   Upload `aur_key.pub` to your AUR account.
3. In the GitHub repo: Settings -> Secrets and variables -> Actions -> New repository
   secret `AUR_SSH_PRIVATE_KEY` = the contents of `aur_key` (the private key). Then delete
   the local copy of the key if you don't need it.
4. Run the workflow once (Actions -> Update botmux-bin -> Run workflow, tick *publish*).
   The first push to `ssh://aur@aur.archlinux.org/botmux-bin.git` creates the package.

Without the secret the workflow still keeps `PKGBUILD`/`.SRCINFO` in your repo current.

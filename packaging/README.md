# Package-manager definitions

These definitions install the same signed and notarized universal application
published on the Window Layouts GitHub Releases page. They do not rebuild or
re-sign the application.

## MacPorts

The candidate Portfile is at
`macports/aqua/window-layouts/Portfile`, matching the directory structure used
by the official `macports/macports-ports` repository.

Validate a release before opening an upstream pull request:

```bash
cd packaging/macports/aqua/window-layouts
port lint --nitpick
sudo port -v checksum
sudo port -v destroot
```

The final upstream file belongs at `aqua/window-layouts/Portfile`. It was
submitted in [MacPorts pull request #34326](https://github.com/macports/macports-ports/pull/34326).
Once that pull request is accepted, users will be able to install it with:

```bash
sudo port selfupdate
sudo port install window-layouts
```

MacPorts installs Aqua applications under its configured
`applications_dir`, normally `/Applications/MacPorts`.

## Homebrew

The reference Cask is at `homebrew/Casks/window-layouts.rb`. It is published in
the public [`baddison2005/homebrew-tap`](https://github.com/baddison2005/homebrew-tap)
repository as `Casks/window-layouts.rb`. The separate tap is required until
Window Layouts satisfies the notability requirements of the official
`Homebrew/homebrew-cask` repository.

Validate it on a Mac with Homebrew installed:

```bash
brew audit --cask --new baddison2005/tap/window-layouts
brew style --cask baddison2005/tap/window-layouts
brew install --cask baddison2005/tap/window-layouts
brew uninstall --cask baddison2005/tap/window-layouts
```

Users can install it with:

```bash
brew tap baddison2005/tap
brew install --cask window-layouts
```

## Updating for a release

Both package managers intentionally pin an immutable release and checksum.
Their update mechanisms fetch a revised definition; they do not execute
dynamic package code that downloads an unchecked “latest” asset.

For every stable Window Layouts release:

1. Publish and test the signed, notarized DMG.
2. Set `version` in both definitions.
3. Set the DMG's SHA-256 digest in both definitions.
4. Set its RIPEMD-160 digest and byte size in the Portfile.
5. Run the validation commands above.
6. Update the Homebrew tap and submit a MacPorts update pull request.

The Homebrew `livecheck` block and MacPorts `livecheck` fields detect newer
GitHub releases, but a reviewed definition update is still required before a
package manager distributes that version.

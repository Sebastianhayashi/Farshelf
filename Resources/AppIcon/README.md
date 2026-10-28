# Farshelf icon

The mark shows two separate archive cards and a warm media preview that remains identifiable when its source is away. There is no folder, cloud, cleanup, or backup symbol.

- `AppIcon.icon` is the macOS 26 Icon Composer source. Its three foreground groups use unmasked, sharp-edged SVG layers; macOS applies its own corner mask and material.
- `appicon.svg` is the flattened 1024 px fallback artwork. `appicon-small.svg` removes image detail for tiny sizes.
- `../../docs/logo.svg` is the same flattened mark for the repository README.
- `../AppIcon.icns` is the pre-macOS-26 fallback. Rebuild it whenever the source artwork changes; the fallback and the Icon Composer icon must match.
- The existing tray icons and other-platform product resources are separate assets and need their own QA before any application-wide rename.

Check at 16, 32, 64, and 1024 px in light and dark surroundings. See Apple's app icon and Icon Composer guidance. Do not bake the rounded mask, reflections, or material shadows into Icon Composer layers.

Source palette: background #10254A, archive #28599E / #4586D6, front card #E4F3FB, preview #FFC466 / #B84F44.

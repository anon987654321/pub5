# Shared source fonts

The RAILS shared engine serves these assets from `/fonts`. The CSS makes no third-party font requests.

## Source Sans 3

Proportional sans serif variable font, weights 200 through 900, normal and italic.

Upstream: https://github.com/adobe-fonts/source-sans  
Files: `WOFF2/VF/SourceSans3VF-Upright.ttf.woff2`, `WOFF2/VF/SourceSans3VF-Italic.ttf.woff2`  
License: `SourceSans3-OFL.txt` (SIL Open Font License 1.1).

JetBrainsMono Nerd Font is the one bundled monospace face (`--font-mono`).


## JetBrainsMono Nerd Font in terminal emulators

The shared engine serves regular and bold WOFF2 faces to browser CSS. PuTTY
and Termux need a native fixed-width font installed on the device; they cannot
use the web WOFF2 assets as their terminal font. Install the JetBrainsMono
Nerd Font TTF/OTF build locally and select it in PuTTY's Window → Appearance
font picker or Termux's More → Style → Choose Font menu. Termux can load a TTF
from ~/.termux/font.ttf; run termux-reload-settings after changing it.

The [official Nerd Fonts JetBrainsMono release archive](https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz)
contains the native TTF/OTF variants, including the Mono build. Select that
installed face in PuTTY or Termux.

The WOFF2 assets are web projections, not an installer for the operating
system or terminal. MASTER never changes the emulator's font or size.

Keep the license text with the font binaries in source distributions and deployments.

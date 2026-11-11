# MASTER on Android

The supported Android runtime for MASTER's normal CLI is **Ubuntu or Debian under PRoot-Distro**. Native Termux Ruby is not a supported runtime. The Termux app remains the host that installs and enters one of those guests; MASTER's CLI runs only inside a verified supported guest.

A direct `bin/master` invocation from a Termux host with Ruby installed hands off to the installer and enters a supported guest. A direct invocation from a PRoot-Distro guest checks both the PRoot container marker and `/etc/os-release`; it permits only Ubuntu or Debian and refuses any other or unverified guest with status 78. Desktop and OpenBSD continue through the same Ruby entrypoint.

## Install and launch

Use a maintained Termux build. Preview the installer from any POSIX shell without changing the device, installing packages, touching files or contacting GitHub:

    curl -fsSL https://raw.githubusercontent.com/anon987654321/pub5/main/MASTER/bin/master-mobile-install | sh -s -- --demo

The first run installs Termux host tools if missing, fast-forwards a clean canonical checkout, reuses an installed Ubuntu guest or else Debian, and installs Ubuntu only when neither is present. It builds the pinned Ruby and locked bundle in the selected guest, verifies the normal CLI boot, then starts MASTER:

    curl -fsSL https://raw.githubusercontent.com/anon987654321/pub5/main/MASTER/bin/master-mobile-install | sh

The installer checks Termux's expected PREFIX and non-root host account. It permits only the canonical HTTPS pub5 repository, keeps the checkout below Termux HOME, and refuses symlink or non-Git collisions. Existing checkouts must have the canonical origin, the expected branch and a clean working tree before the fast-forward. Existing Ubuntu or Debian guests are reused and never reset. With no supported guest installed, the default is Ubuntu; `--debian` selects Debian explicitly.

Both guests receive the required Linux build libraries. The installer builds the exact Ruby version from `.ruby-version` under `/opt/rubies/`, then runs `bin/deps install`, `bin/deps check` and `bin/deps boot`. It records both the guest and pinned Ruby in `/etc/master-mobile-runtime`. Future launches reuse the selected guest and pinned Ruby.

The installer adds `~/.local/bin/master` as a Termux-host launcher. Reload `~/.bashrc`, then run `master`; it enters the selected guest and forwards arguments to `bin/master`. Running `bin/master` from Termux when native Ruby is already installed also follows the automatic install-and-entry path. To provision without starting the CLI, use `--no-launch`. Arguments after `--` are forwarded.

PRoot-Distro documents the Ubuntu and Debian images and their `install` / `login` workflows. It is a user-space Linux environment, not Android root or a kernel security boundary. [PRoot-Distro documentation](https://github.com/termux/proot-distro).

## Termux host and Android capabilities

The Ubuntu or Debian guest is the supported runtime for the normal text CLI. Termux remains the host for PRoot-Distro and the Termux:API companion app. Android camera, microphone, speech, browser bridge and other native device features are separate host capabilities; an Ubuntu CLI boot is not proof that those integrations are ready. The installer does not grant Android permissions or claim hardware readiness.

## Provider sign-in

MASTER delegates sign-in to each provider's own CLI; it never copies OAuth tokens or session files into its own store. From the normal interactive prompt:

    /model auth
    /model auth login claude
    /model auth login chatgpt
    /model auth login grok

Claude uses its browser sign-in. On mobile or a headless terminal, Codex and Grok use their device-code flow when the installed CLI/account supports it. Use `--browser` to force the provider's regular browser flow, or `--device-auth` to request device code explicitly. `/model auth status` asks each provider CLI for its own status; installed is not reported as authenticated when the CLI cannot prove sign-in.


## Optional local model fallback

The local llama.cpp lane is a last resort, not a boot-time download. Build it on the Termux host or in the supported guest and expose its binary and model to the guest explicitly; MASTER does not download model weights automatically. Start with a modest context because large contexts can exhaust phone memory:

    pkg install git cmake libandroid-spawn
    git clone https://github.com/ggml-org/llama.cpp
    cd llama.cpp
    cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build --config Release -j2
    export PATH="$HOME/llama.cpp/build/bin:$PATH"
    mkdir -p "$HOME/models"
    export MASTER_LLAMA_MODEL="$HOME/models/your-small-quantised-model.gguf"

Choose a quantised model that fits the phone's available memory and storage. The fallback starts with a 4096-token context and two CPU threads. Keep the model under Termux's private home directory and add an explicit PRoot bind for its directory before setting `MASTER_LLAMA_MODEL` inside the guest. Restart MASTER, then inspect `/model list`. No local HTTP server or OpenAI-compatible endpoint is started.


## Use

`bin/master-mobile` and Android integration commands are not part of the Ubuntu CLI readiness proof. Ubuntu and Debian guests are supported for the normal text CLI. Camera, microphone, Termux:API, the browser bridge and speech output remain separate host capabilities; this installer does not claim they work from inside Ubuntu.

A host-side microphone bridge needs an explicit Termux:API adapter and host/guest boundary. Do not grant or assume microphone access merely because the Ubuntu CLI boots. The existing local permission commands remain:

    /privacy grant microphone --confirm "GRANT microphone"
    /privacy grant speech_recognition --confirm "GRANT speech_recognition"

The same grants protect microphone capture in both the terminal and browser face, and expire after one hour. Grant them from the normal `bin/master` session before using the browser's listen button. Android still requires microphone permission for the Termux app, the Termux:API companion app, and `pkg install termux-api`. `/voice on` enables spoken replies in the terminal; the mobile browser bridge speaks each reply through Termux:API. Use the normal Termux app user for the Termux:API commands; the supported PRoot guest is for the Linux CLI/build and is not the mobile API readiness path.

## Security boundaries

MASTER runs as the Termux app user, not root. Root indicators and Android properties are heuristics or observations, not proof of device integrity. This mobile doctor checks the local MASTER checkout and its private state directory; it cannot attest that all Android apps or the operating system are malware-free. A clean `git diff` is not a cryptographic supply-chain attestation, and this installer currently follows the selected branch rather than a pinned signed release.

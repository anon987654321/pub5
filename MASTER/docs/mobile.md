# MASTER on a phone

MASTER runs on Android under Termux with the same soul.yml and laws.yml as desktop. Mobile readiness is measured locally; this is not a claim to scan or secure the whole Android operating system.

## Install

Use a maintained Termux build. Preview the installer from any POSIX shell without changing the
device, installing packages, touching files or contacting GitHub:

    curl -fsSL https://raw.githubusercontent.com/anon987654321/pub5/main/MASTER/bin/master-mobile-install | sh -s -- --demo

The real install command follows only after reviewing that plan:

    curl -fsSL https://raw.githubusercontent.com/anon987654321/pub5/main/MASTER/bin/master-mobile-install | sh

The installer runs a fail-closed preflight before package operations: it requires Termux's expected PREFIX, refuses root, permits only the canonical HTTPS pub5 repository, keeps the install directory below Termux HOME, refuses symlink/non-Git collisions, and verifies the checkout origin and clean working tree before running project code.

The installer installs and checks the pinned Ruby bundle through `bin/deps install` and `bin/deps check`, proves the normal CLI entry point with `bin/deps boot`, then installs Falcon and runs `bin/master-mobile doctor`. The doctor checks Termux, required packages, Falcon, the canonical Git origin, a clean checkout, private mobile state-directory permissions and the bridge port; it changes only the mobile state directory's mode to 0700. A successful install therefore proves more than the presence of the bridge server: the regular MASTER CLI has also completed its boot path.

Termux from F-Droid is the build that still receives updates. Install Termux:API from the same place if you want speech features; optional speech backends do not block installation.

## Debian/Ubuntu build path with PRoot-Distro

Use this route when the native Termux Ruby or a native gem build does not
complete on the device. It gives MASTER a regular glibc Linux userland and
builds the exact Ruby version recorded in the checkout. It is a build/runtime
fallback for the normal CLI; it is not a claim that every Termux camera, speech
or Android integration works inside the guest.

On the Termux host, install PRoot-Distro and create the Debian guest once:

    pkg update -y
    pkg install -y git curl proot-distro
    proot-distro install debian

From the pub5 checkout in Termux, bind the checkout into the guest and build
Ruby from the repository's version pin. The bind keeps the Git worktree in
Termux home; the Ruby installation and system libraries persist inside Debian.

    cd "$HOME/pub5"
    proot-distro login debian --bind "$PWD:/pub5" -- bash -lc '
      set -eu
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates git curl build-essential autoconf bison pkg-config zsh \
        libssl-dev libreadline-dev zlib1g-dev libffi-dev libyaml-dev \
        libsqlite3-dev libvips-dev libxml2-dev libxslt1-dev \\
        libgdbm-dev libdb-dev libncurses-dev

      if ! command -v ruby-build >/dev/null 2>&1; then
        git clone --depth 1 https://github.com/rbenv/ruby-build.git /tmp/ruby-build
        PREFIX=/usr/local /tmp/ruby-build/install.sh
      fi

      ruby_version="$(cat /pub5/.ruby-version)"
      mkdir -p /opt/rubies
      ruby_home="/opt/rubies/$ruby_version"
      if [ ! -x "$ruby_home/bin/ruby" ]; then
        ruby-build "$ruby_version" "$ruby_home"
      fi
      export PATH="$ruby_home/bin:/usr/local/bin:$PATH"
      ruby --version
      cd /pub5/MASTER
      ruby bin/deps install
      ruby bin/deps check
      ruby bin/deps boot
    '

To start the normal MASTER CLI later, enter the existing guest again:

    proot-distro login debian --bind "$HOME/pub5:/pub5" -- bash -lc '
      ruby_version="$(cat /pub5/.ruby-version)"
      export PATH="/opt/rubies/$ruby_version/bin:/usr/local/bin:$PATH"
      cd /pub5/MASTER
      bin/master
    '

The guest's container marker is deliberately treated as Linux, not as the
native Termux host. This prevents MASTER from trying to run Termux's package
bootstrap from inside Debian. Use bin/master-mobile doctor from the real
Termux app environment, not as a readiness verdict for the Debian guest.
PRoot-Distro supplies a fake root for the guest package manager; it is not
Android root and cannot provide kernel-level root, systemd or container
isolation. The normal Termux:API speech/camera path remains a separate native
Termux capability and must be tested there.


## Provider sign-in

MASTER delegates sign-in to each provider's own CLI; it never copies OAuth tokens or session files into its own store. From the normal interactive prompt:

    /model auth
    /model auth login claude
    /model auth login chatgpt
    /model auth login grok

Claude uses its browser sign-in. On mobile or a headless terminal, Codex and Grok use their device-code flow when the installed CLI/account supports it. Use `--browser` to force the provider's regular browser flow, or `--device-auth` to request device code explicitly. `/model auth status` asks each provider CLI for its own status; installed is not reported as authenticated when the CLI cannot prove sign-in.

## Optional local model fallback

The local llama.cpp lane is a last resort, not a boot-time download. It appears only when both `llama-cli` and a readable GGUF file are present. Upstream documents building the CLI inside Termux; start with a modest context because large contexts can exhaust phone memory:

    pkg install git cmake libandroid-spawn
    git clone https://github.com/ggml-org/llama.cpp
    cd llama.cpp
    cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build --config Release -j2
    export PATH="$HOME/llama.cpp/build/bin:$PATH"
    mkdir -p "$HOME/models"
    export MASTER_LLAMA_MODEL="$HOME/models/your-small-quantised-model.gguf"

Choose a quantised model that fits the phone's available memory and storage; MASTER does not download one or assume the device can run a particular size. The fallback starts with a 4096-token context and two CPU threads. Keep the model under Termux's private home directory for reliable file access. Restart MASTER after setting the environment variable, then inspect `/model list`. No local HTTP server or OpenAI-compatible endpoint is started.

## Use

`bin/master-mobile doctor` measures the phone and exits 0 only when required readiness and integrity checks pass. `bin/master-mobile bridge` serves the animated face at http://127.0.0.1:8765/face; open that URL in the phone browser while the bridge runs. The page uses one explicit listen press, then shows listening, thinking and speaking states. `bin/master-mobile host` runs the face socket alone. The bridge binds loopback because it has no authentication; do not forward port 8765 off the phone.

The normal Reline prompt also supports one deliberate microphone capture with `/listen`. It asks for both local grants before opening the microphone:

    /privacy grant microphone --confirm "GRANT microphone"
    /privacy grant speech_recognition --confirm "GRANT speech_recognition"

The same grants protect microphone capture in both the terminal and browser face, and expire after one hour. Grant them from the normal `bin/master` session before using the browser's listen button. Android still requires microphone permission for the Termux app, the Termux:API companion app, and `pkg install termux-api`. `/voice on` enables spoken replies in the terminal; the mobile browser bridge speaks each reply through Termux:API. Use the normal Termux app user for the Termux:API commands; the Debian PRoot route above is for the Linux CLI/build and is not the mobile API readiness path.

## Security boundaries

MASTER runs as the Termux app user, not root. Root indicators and Android properties are heuristics or observations, not proof of device integrity. This mobile doctor checks the local MASTER checkout and its private state directory; it cannot attest that all Android apps or the operating system are malware-free. A clean `git diff` is not a cryptographic supply-chain attestation, and this installer currently follows the selected branch rather than a pinned signed release.

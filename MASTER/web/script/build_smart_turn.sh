#!/bin/sh
# Fetch the Smart Turn endpointing assets into public/.
#
# Not tracked in git since 8 November 2026 (TREE_CONTRACTS.md, "Vendorables
# trend out of git"): the pinned onnxruntime-web build and the pinned
# smart-turn model are fetched here — at deploy time when absent, or by hand —
# and verified against the sha256 digests below before anything lands in
# public/. Provenance is a command plus a digest, not a memory. A host that
# cannot reach npm and Hugging Face serves without smart_turn; the feature is
# default-off (?smart_turn=1), so the tree still boots and serves.
#
#   sh script/build_smart_turn.sh
#
# ~22MB total. onnxruntime-web ships only a threaded WASM build from 1.27; it
# runs single-threaded when SharedArrayBuffer is absent, so no cross-origin
# isolation headers are required.

set -eu

ORT_VERSION=1.27.0
MODEL=smart-turn-v3.2-cpu.onnx
MODEL_REPO=pipecat-ai/smart-turn-v3

# The digests the tree last served when the bytes were tracked. A download
# that does not match these is not the artifact the front end was built
# against: stop, never ship it.
ORT_WASM_MIN_MJS_SHA256=9608e98a3fba9716f0cbd0bca0c94808b71dae2e9265ca3fe742ddc393a53ebc
ORT_WASM_SIMD_MJS_SHA256=0a1e718d99c41b22c21f2520ff4f9e883a6b5533856e398d21816ee8eb8185d3
ORT_WASM_SIMD_WASM_SHA256=d1ab1b94b16a65b29d710d0b587b29e7bed336827577623913479b8afe8113e6
MODEL_SHA256=2bb026316b14a660486a75b1733cd3fbab8c2fd0314dc9af7be49f8cca967e4f
MODEL_MIN_BYTES=4000000

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vendor="$root/public/vendor/onnxruntime"
models="$root/public/models"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# sha256 -q is OpenBSD base; sha256sum and shasum cover Linux and macOS.
digest() {
  if command -v sha256 >/dev/null 2>&1; then
    sha256 -q "$1"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

expect() { # <file> <digest> — dies when the bytes are not the pinned ones
  actual=$(digest "$1")
  if [ "$actual" != "$2" ]; then
    printf 'smart_turn: %s digest mismatch\n  expected %s\n  got      %s\n' \
      "$1" "$2" "$actual" >&2
    exit 1
  fi
}

mkdir -p "$vendor" "$models"

printf 'smart_turn: onnxruntime-web %s\n' "$ORT_VERSION"
curl -sSL --fail -o "$work/ort.tgz" \
  "https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-${ORT_VERSION}.tgz"
tar xzf "$work/ort.tgz" -C "$work" \
  package/dist/ort.wasm.min.mjs \
  package/dist/ort-wasm-simd-threaded.mjs \
  package/dist/ort-wasm-simd-threaded.wasm
expect "$work/package/dist/ort.wasm.min.mjs" "$ORT_WASM_MIN_MJS_SHA256"
expect "$work/package/dist/ort-wasm-simd-threaded.mjs" "$ORT_WASM_SIMD_MJS_SHA256"
expect "$work/package/dist/ort-wasm-simd-threaded.wasm" "$ORT_WASM_SIMD_WASM_SHA256"
cp "$work/package/dist/ort.wasm.min.mjs" \
   "$work/package/dist/ort-wasm-simd-threaded.mjs" \
   "$work/package/dist/ort-wasm-simd-threaded.wasm" "$vendor/"

printf 'smart_turn: %s from %s\n' "$MODEL" "$MODEL_REPO"
curl -sSL --fail -o "$work/$MODEL" \
  "https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL}"

# An HTML error page saved under a .onnx name is the failure mode worth
# catching: it is small, and it would 404-as-200 all the way to the browser.
# The digest is the binding check; the size is the tripwire before it.
size=$(wc -c < "$work/$MODEL" | tr -d ' \t')
if [ "$size" -lt "$MODEL_MIN_BYTES" ]; then
  printf 'smart_turn: %s is only %s bytes - fetch failed\n' "$MODEL" "$size" >&2
  exit 1
fi
expect "$work/$MODEL" "$MODEL_SHA256"
mv "$work/$MODEL" "$models/$MODEL"

printf 'smart_turn: vendored, digests verified\n'
ls -l "$vendor" "$models"

# Soulseek

MASTER connects to an existing [slskd](https://github.com/slskd/slskd) daemon through its versioned HTTP API. slskd owns the Soulseek network session and transfer engine; MASTER owns command admission, local collection inventory and the acquisition boundary.

## Configure

Install and configure slskd natively on the workstation. Keep its web/API listener bound to loopback unless a remote endpoint is required. Create an API key with the minimum required read/write role, then export it only in the MASTER process environment:

```sh
export MASTER_SLSKD_URL=http://127.0.0.1:5030
export MASTER_SLSKD_API_KEY='your-slskd-api-key'
MASTER/bin/master
```

The default endpoint is loopback HTTP on port 5030. A remote endpoint must use public HTTPS on port 443 and pass MASTER's pinned-address SSRF guard. Do not expose the slskd API directly to the public internet. The API key is never written to repository files or plugin state.

## Actions

```text
/plugin info soulseek
/plugin run soulseek status {}
/plugin run soulseek search {"query":"J Dilla Jay Dee"}
/plugin run soulseek results {"search_id":"<UUID returned by search>"}
/plugin run soulseek downloads {}
/plugin run soulseek library {"path":"~/Music"}
/plugin run soulseek gaps {"path":"~/Music","queries":["J Dilla - Welcome 2 Detroit","Hugh Mundell - Africa Must Be Free"]}
/plugin run soulseek queue {"search_id":"<UUID>","username":"<peer>","filename":"<exact result path>","size":1234567,"rights_basis":"artist_authorized","consent":true}
```

Library scans read filenames and sizes only. They do not open, tag, move, rename or delete audio. Gap matching is a filename heuristic, not an audio fingerprint or proof that two releases are identical.

## Rebuild and audit a collection

Compare existing path-list exports without counting directory names as tracks:

```text
/plugin run soulseek manifest {"paths":["~/MusicExports/0day.txt","~/MusicExports/samples.txt","~/MusicExports/reggae.txt"]}
```

Build a structured catalogue from an actual local music folder. Create the destination directory first; exports are written outside the music folder and require explicit consent:

```text
/plugin run soulseek catalog {"path":"~/Music","output_path":"~/.master/music/catalog.json","consent":true}
/plugin run soulseek duplicates {"path":"~/Music","mode":"candidates"}
/plugin run soulseek duplicates {"path":"~/Music","mode":"sha256"}
/plugin run soulseek quality {"path":"~/Music"}
```

The catalogue groups files by their containing folder and records relative paths, sizes, formats and filename-derived artist/album/title/year hints. It reports folders without clear artist/year hints and tracks without a track-number hint. These are naming-based metadata gaps, not a scan of embedded ID3/Vorbis/MP4 tags; it does not read embedded tags or audio. Manifest comparisons report exact path overlap only; different paths do not establish different recordings. Duplicate candidates share a normalized filename and size, while `sha256` verifies byte-identical content by reading each audio file. Hashing can take time on large libraries. Both modes are reports only: nothing is deleted or reorganised. Existing catalogue files are not overwritten unless `overwrite: true` is also supplied with consent.

The `quality` action is structural triage: it reports common extension families, empty files and very small files for manual review. It does not decode audio or establish bitrate, sample rate, clipping or audible fidelity; small files may be intentional samples or short clips.

Search and result inspection do not download files. Queueing requires explicit `consent: true`, the exact unlocked filename and size from the named search result, and a rights basis admitted by MASTER's canonical plugin policy (`public_domain`, `open_license`, `artist_authorized` or `rights_owned`). One file is queued per call. Bulk acquisition is disabled. The rights basis is an operator attestation, not a legal determination; personal possession or personal-use intent alone is not a rights basis.

MASTER does not bypass peer queues, locked shares, DRM, paywalls or access controls. Verify the recording, edition, source and licence before queueing. slskd's configured download directory and transfer limits remain authoritative.

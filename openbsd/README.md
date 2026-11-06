# OpenBSD host boundary

vm23 is the only production host. Host facts live in registry/hosts.yml; product/process facts live in registry/apps.yml. Service configuration is retained under production/ as source, with original Git blob identities recorded in provenance.yml.

## Preserved inputs

The production PF, relayd, httpd, rc.conf.local and service scripts are copied verbatim from pub4. The 1-vCPU/1-GiB resource budget, resource guard, uptime and certificate monitors are also preserved. Recovery inputs include the inert Litestream configuration, the legacy on-disk restore helper and the pull-based dr-pull tool. Every preserved file has its original Git blob SHA in provenance.yml.

The Litestream configuration states that the service is inert and disabled. The presence of a backup or restore script does not prove that a backup exists, that replication has run, or that a restore succeeded.

## Safety boundary

Rehearsal verifies source identity and local contracts only. A live vm23 observation, public canary, backup result, restore drill or deployment is never inferred from a local parse. The Ruby deploy tool cannot ship: no signed live-evidence verifier or release transport has been implemented. No SSH, rcctl, pfctl, relayctl or production write is performed by this repository change.

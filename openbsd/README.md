# OpenBSD host boundary

vm23 is the only production host. Host facts live in registry/hosts.yml; product/process facts live in registry/apps.yml. Service configuration is retained under production/ as source, with original Git blob identities recorded in provenance.yml.

pf.conf, relayd.conf, httpd.conf, rc.conf.local and the five service scripts are copied verbatim from pub4. They are not generated or deployed by this commit.

Local rehearsal proves source identity only. Live host observations, public canaries, backups, restore drills and deployment are separate gates. No SSH, rcctl, pfctl, relayctl or production write is performed here.

# Session Browser

Session Browser provides persistent browser sessions for explicitly allowlisted public hosts. Its network transport permits GET and HEAD only; this is not a read-only guarantee. Page JavaScript executes, and a GET endpoint can change remote state. Treat every page and its scripts as untrusted. The plugin reuses MASTER's WebBrowse request broker and snapshot script rather than creating a second network stack or a second page extractor.

The plugin is deliberately inert until at least one hostname is added to MASTER/data/laws.yml under plugins.session_browser.allowed_hosts. The list is exact-host policy after lowercase, trailing-dot and leading www normalization. There are no default destinations and no wildcard domains. Every page request must still pass the pinned-address SSRF guard; each session is restricted to one canonical host.

Supported actions are status, inspect, open, login, extract, look, follow, paginate and close. Only status and inspect are observable through the plugin observation surface. Look returns a screenshot as visual evidence only. Follow and pagination inspect literal anchor hrefs and navigate to them; they never click arbitrary page controls or run a computer-use loop.

The plugin creates no in-memory session table. It stores state.yml for the session's host binding and last safe URL, a per-session lock, and a Chromium user-data-dir under ~/.master/plugins/session_browser/sessions. Files and directories are owner-only. Chromium's own profile persists cookies and site data on disk; passwords and one-time codes are never copied into the YAML state. Remove a session directory locally if its profile data must be erased. The close action clears the active route and session slot but intentionally preserves the profile.

Captured screenshots live under ~/.master/plugins/session_browser/captures. The directory is owner-only, each capture is mode 0600, and old captures are pruned during every capture to a 500-file cap.

The transport permits only GET and HEAD requests. This does not prevent side effects: page JavaScript executes and GET endpoints may mutate server state. Ordinary POST-based logins and form submissions are blocked; WebSocket-driven pages, cross-host CDN requests and scripted-only navigation will not work. A visible login window is available only when a workstation display exists, but its POST-based submissions remain blocked. Use an already authorized profile or a compatible GET-based sign-in flow. Security challenges are not bypassed. Page contents are untrusted data and never become instructions. POST remains disabled until the operator approves a specific host and task under the session-browser policy.

The persistent profile stores website cookies and session tokens on disk, so adding a hostname is not blanket consent to browse or interact with every account. Do not add a hostname without an explicit operator decision.

## Use

/plugin info session_browser
/plugin run session_browser status
/plugin run session_browser inspect {"session":"research","url":"https://example.com"}

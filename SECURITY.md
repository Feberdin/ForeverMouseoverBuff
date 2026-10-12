# Security and privacy

Do not post access tokens, complete SavedVariables, player whispers or personal
configuration files in public reports. Until a private reporting channel exists,
request a private contact through the project owner's normal channel without
including exploit details or sensitive data in the first message.

No credentials ship in the addon. Receiver preferences use a bounded in-game
addon-message exchange; they are a convenience preference, not authentication.
Someone can manually imitate the public FMB greeting marker.

Ranking records are self-reported. A modified client or edited local file can
invent plausible events. Encryption of a file whose key is also on that client
does not solve this. Server-side deduplication, known spell IDs and limits reduce
accidental duplication and implausible submissions; they do not establish honest
play, character ownership or a verified competitive rank.

Since 0.7.1, local aggregate counters use a fixed binary/Base64 envelope and an
unkeyed SHA-256 checksum. This detects changed or corrupt bytes without a matching
checksum; it is not encryption. A file owner can recompute it, restore an older
valid record or alter the addon. Valid legacy values migrate once on load; damaged
records are preserved and counting pauses. Optional event exports and historical
backups remain readable. No authenticity claim is made for either representation.

The optional companion reads a bounded SavedVariables literal without executing
Lua. Ranking upload selects only ranking fields and requires deliberate
enrollment/consent. Its separate local `diagnostics` command has no enrollment,
network or token use; it projects only fixed diagnostic fields.

Since 0.7.2, diagnostic history retains at most 64 structured events and 40
legacy codes, alongside bounded counters and a small settings/client snapshot.
No names, GUIDs, messages or raw error strings are recorded. The reader never
executes SavedVariables and omits unknown fields; a file snapshot is not a
live game-memory inspection. See [DIAGNOSTICS.md](DIAGNOSTICS.md).
Tokens are stored outside the game/source folders with restricted permissions.
The local web dashboard must remain on loopback until hosting, TLS, operator
information, privacy, moderation, backup retention and deletion are reviewed.

Release preparation uses an explicit own-file allowlist and rejects known private
computer paths or credential patterns. This helps prevent mistakes but is not an
exhaustive secret scanner. Review all diffs and the manifest before publication.
SHA-256 manifests detect changed package bytes; they do not verify game events.

If CurseForge API automation is added later, access a key only through the
`CURSEFORGE_API_KEY` environment variable. Never commit, print, embed or request
its literal value. No upload API, secret or project ID is configured here.

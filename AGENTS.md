# Repository guidance

This is the canonical instruction file for this repository. Claude Code loads it through
`CLAUDE.md`.

## Start here

- Inspect branch, upstream divergence, status, and diff before editing.
- Preserve pre-existing changes and keep unrelated work out of the patch.
- Use the repository's existing runtime, package manager, framework, and deployment model.
- Do not refactor an existing project into the preferred new-project stack unless explicitly requested.
- Verify current documentation before changing version-dependent dependencies or hosting behavior.

## Project

This automation mirrors the SUSE VMDP ISO into GitHub Releases.

It is a shell and GitHub Actions mirror workflow.

## Project rules

- Treat upstream artifacts as untrusted until source, version, and integrity checks succeed.
- Do not publish or replace release assets without verifying the exact upstream version.
- Keep scheduled automation zero-touch when healthy and fail loudly when intervention is required.
- Preserve the Windows installation commands and quoting behavior.
- Read back the resulting GitHub release and asset metadata after mutations.

## Commands

- `bash -n scripts/mirror.sh`: syntax validation
- `shellcheck scripts/mirror.sh`: lint when ShellCheck is available
- Use a non-publishing or temporary validation path before changing release behavior

## Verification

Run the relevant checks and exercise the affected workflow, endpoint, or generated artifact.
State clearly when authenticated, database, deployment, or live verification was not possible.

## Maintaining instructions

Update `AGENTS.md` when verified, durable repository behavior changes. Keep it concise and
move detailed explanations into `docs/`. Keep `CLAUDE.md` as the compatibility import
unless Claude-specific guidance is genuinely required.

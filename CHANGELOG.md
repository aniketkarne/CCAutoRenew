# Changelog

## Unreleased

### Fixed

- `restart` now keeps every setting that isn't named on the command line
  (start/stop times, custom message, day filter) — it previously deleted
  all four, silently reverting a scheduled daemon to 24/7 monitoring with
  default greetings despite the README documenting the opposite.
- The launchd bootstrap starts the daemon with `--keep-config`, so a
  configured schedule survives reboots instead of being wiped at login.
- Documented `--at 'YYYY-MM-DD HH:MM'` / `--stop 'YYYY-MM-DD HH:MM'` values
  (without seconds) now parse on macOS — BSD `date -f` rejects the form the
  README and the error message both advertise.
- End-of-day rollover checks the newly scheduled day, not the day that just
  ended, so the first off-day of a stretch is skipped in one step instead of
  waking every 5 minutes to ask "is it time yet?".
- `--days all` is understood as an explicit "clear the filter" again (the
  normalizer swallowed the alias, so it was indistinguishable from a missing
  `--days`).
- The daemon handles SIGTERM during its sleep cycles immediately; `stop`
  used to burn its full 10-second grace period and end in `kill -9` because
  bash defers traps until the running `sleep` exits.
- Stop time is validated after start time whether either was just set or
  kept from a previous run.

### Added

- `test-schedule-persistence.sh` — sandboxed regression tests for restart
  persistence, explicit setting clears, both time formats, source-safety of
  the daemon script, and day-rollover skipping. Runs in CI alongside
  shellcheck.
- Empty values clear individual settings on restart: `--at ""`, `--stop ""`,
  `--message ""`, `--days all`.
- The daemon script is sourceable (running it as a script is unchanged) so
  tests can exercise its scheduling helpers directly.

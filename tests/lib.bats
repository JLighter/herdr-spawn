#!/usr/bin/env bats
# Unit tests for the pure functions in lib.sh (no herdr server needed).

setup() {
  . "$BATS_TEST_DIRNAME/../lib.sh"
}

# ── slugify ───────────────────────────────────────────────────────────

@test "slugify: simple sentence" {
  run slugify "fix the pagination bug"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-the-pagination-bug" ]
}

@test "slugify: accents transliterated, locale-independent" {
  run slugify "Réponds à ma requête très vite"
  [ "$status" -eq 0 ]
  [ "$output" = "reponds-a-ma-requete-tres-vite" ]
}

@test "slugify: punctuation collapsed to dashes, none at the edges" {
  run slugify "  fix: login/logout !! "
  [ "$status" -eq 0 ]
  [ "$output" = "fix-login-logout" ]
}

@test "slugify: truncated to 40 characters" {
  run slugify "a really long sentence that goes way past the forty character limit"
  [ "$status" -eq 0 ]
  [ "${#output}" -le 40 ]
}

@test "slugify: fully non-ascii prompt yields an empty string" {
  run slugify "日本語のみ"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "slugify: multi-line prompt collapses to one slug" {
  run slugify $'first line\nsecond line'
  [ "$status" -eq 0 ]
  [ "$output" = "first-line-second-line" ]
}

# ── herdr_error_code ──────────────────────────────────────────────────

@test "herdr_error_code: extracts the code from a CLI error" {
  run herdr_error_code '{"error":{"code":"agent_pane_busy","message":"…"},"id":"x"}'
  [ "$output" = "agent_pane_busy" ]
}

@test "herdr_error_code: success response yields an empty string" {
  run herdr_error_code '{"id":"x","result":{"type":"ok"}}'
  [ -z "$output" ]
}

@test "herdr_error_code: non-JSON output yields an empty string without failing" {
  run herdr_error_code "plain text failure"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── unique_branch ─────────────────────────────────────────────────────

@test "unique_branch: bare name when the branch does not exist" {
  cd "$(mktemp -d)" && git init -q \
    && git -c user.name=test -c user.email=test@test commit -q --allow-empty -m init
  run unique_branch "agent/new-task"
  [ "$output" = "agent/new-task" ]
}

# ── smart_slug ────────────────────────────────────────────────────────

@test "smart_slug: slugifies whatever slug_command answers" {
  slug_command='printf "My Fancy Name!"'
  slug_wait=3
  run smart_slug "whatever task"
  [ "$status" -eq 0 ]
  [ "$output" = "my-fancy-name" ]
}

@test "smart_slug: a hung slug_command times out to an empty slug" {
  slug_command='sleep 10'
  slug_wait=1
  run smart_slug "whatever task"
  [ -z "$output" ]
}

@test "smart_slug: unset slug_command fails fast" {
  slug_command=""
  run smart_slug "whatever task"
  [ "$status" -ne 0 ]
}

@test "unique_branch: -2 then -3 suffix on collision" {
  cd "$(mktemp -d)" && git init -q \
    && git -c user.name=test -c user.email=test@test commit -q --allow-empty -m init
  git branch "agent/task"
  run unique_branch "agent/task"
  [ "$output" = "agent/task-2" ]
  git branch "agent/task-2"
  run unique_branch "agent/task"
  [ "$output" = "agent/task-3" ]
}


#!/usr/bin/env bats
# Integration tests for the popup UI, driven through a real pty with
# expect. SPAWN_UI_DRY_RUN=1 prints the resolved prompt/branch instead
# of launching anything — no herdr server involved.

setup() {
  command -v expect >/dev/null 2>&1 || skip "expect not available"
  tmp=$(mktemp -d)
  export SPAWN_UI_DRY_RUN=1
  export HERDR_PLUGIN_CONFIG_DIR="$tmp/config" HERDR_PLUGIN_STATE_DIR="$tmp/state"
  mkdir -p "$HERDR_PLUGIN_CONFIG_DIR" "$HERDR_PLUGIN_STATE_DIR"
  repo="$tmp/repo"
  mkdir "$repo"
  git -C "$repo" init -q
  git -C "$repo" -c user.name=test -c user.email=test@test commit -q --allow-empty -m init
  cd "$repo"
}

@test "ui: the branch slug refreshes live while typing" {
  run expect "$BATS_TEST_DIRNAME/ui-driver.exp" live-slug
  [ "$status" -eq 0 ]
}

@test "ui: shift+enter submits like a plain enter (herdr's encoding is swallowed)" {
  run expect "$BATS_TEST_DIRNAME/ui-driver.exp" shift-enter-is-enter
  [ "$status" -eq 0 ]
}

@test "ui: esc on an empty line closes the popup without launching" {
  run expect "$BATS_TEST_DIRNAME/ui-driver.exp" esc-empty
  [ "$status" -eq 0 ]
}

@test "ui: esc with text keeps the line" {
  run expect "$BATS_TEST_DIRNAME/ui-driver.exp" esc-keeps-text
  [ "$status" -eq 0 ]
}

@test "ui: tab jumps to the branch line, which is editable" {
  run expect "$BATS_TEST_DIRNAME/ui-driver.exp" edit-branch
  [ "$status" -eq 0 ]
}

@test "ui: a hand-edited branch stops following the prompt" {
  run expect "$BATS_TEST_DIRNAME/ui-driver.exp" manual-branch-sticks
  [ "$status" -eq 0 ]
}

@test "ui: slug_command replaces the basic slug asynchronously" {
  printf "slug_command='printf fix/llm-made-name'\n" > "$HERDR_PLUGIN_CONFIG_DIR/config"
  run expect "$BATS_TEST_DIRNAME/ui-driver.exp" llm-slug
  [ "$status" -eq 0 ]
}

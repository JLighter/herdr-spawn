# README demo — render with: vhs demo/demo.tape (from the repo root)
Output demo/demo.gif

Set FontSize 15
Set Width 880
Set Height 440
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 55ms

Hide
Type "bash demo/setup.sh && source /tmp/herdr-spawn-demo/env.sh && clear"
Enter
Sleep 500ms
Type `clear; bash "$HERDR_PLUGIN_ROOT/ui.sh"`
Enter
Sleep 800ms
Show

# The branch name in the header follows the prompt as you type.
Type "fix the invoice pagination crash"
Sleep 1.5s

# ctrl+g asks the (local) LLM for a better name, asynchronously.
Ctrl+G
Sleep 2.5s

# tab jumps to the branch line for manual edits, tab comes back.
Tab
Sleep 1s
Backspace 6
Sleep 800ms
Type "-panic"
Sleep 1s
Tab
Sleep 800ms

# enter launches: worktree + workspace + agent + prompt.
Enter
Sleep 3.5s

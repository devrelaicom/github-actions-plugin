---
description: Check that gh, actionlint, wrkflw, zizmor, pinact, and jq are installed
allowed-tools: Bash
---

Use the gha-doctor skill to check whether gh, actionlint, wrkflw, zizmor,
pinact, and jq are installed, by running
`${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh`.

Report the result plainly: if everything is installed, say so in one line.
If anything is missing, list each missing tool with the exact install
command the script printed for it. Do not run any install command — only
report what the user would need to run themselves.

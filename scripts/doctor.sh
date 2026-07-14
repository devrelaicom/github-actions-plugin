#!/usr/bin/env bash
# scripts/doctor.sh
# Checks that the tools gha's other scripts depend on are installed.
# Never installs anything - only reports gaps and prints the install
# command the user would run themselves.
set -uo pipefail

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gha-doctor.XXXXXX")"
echo "gha doctor run: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TMP_FILE"

have_brew=0; have_cargo=0; have_go=0; have_pip=0
command -v brew  >/dev/null 2>&1 && have_brew=1
command -v cargo >/dev/null 2>&1 && have_cargo=1
command -v go    >/dev/null 2>&1 && have_go=1
{ command -v pip3 >/dev/null 2>&1 || command -v pip >/dev/null 2>&1; } && have_pip=1

# check_tool <binary> <version-flag...>
check_tool() {
  local name="$1"; shift
  if command -v "$name" >/dev/null 2>&1; then
    local version
    version="$("$name" "$@" 2>&1 | head -1)"
    echo "OK      $name ($version)"
    echo "OK      $name ($version)" >> "$TMP_FILE"
    return 0
  fi
  echo "MISSING $name"
  echo "MISSING $name" >> "$TMP_FILE"
  return 1
}

# install_hint <label> <brew-pkg> <cargo-pkg> <go-module> <pip-pkg>
install_hint() {
  local label="$1" brew_pkg="$2" cargo_pkg="$3" go_mod="$4" pip_pkg="$5"
  local hint=""
  if   [ "$have_brew"  -eq 1 ] && [ -n "$brew_pkg" ];  then hint="brew install $brew_pkg"
  elif [ "$have_cargo" -eq 1 ] && [ -n "$cargo_pkg" ]; then hint="cargo install $cargo_pkg"
  elif [ "$have_go"    -eq 1 ] && [ -n "$go_mod" ];    then hint="go install ${go_mod}@latest"
  elif [ "$have_pip"   -eq 1 ] && [ -n "$pip_pkg" ];   then hint="pip install $pip_pkg"
  else hint="no supported package manager detected on this machine — see the $label project's install docs"
  fi
  echo "  install: $hint"
  echo "  install: $hint" >> "$TMP_FILE"
}

missing=0

check_tool gh --version                || { install_hint gh gh "" "" "";                                                                                  missing=1; }
check_tool actionlint -version         || { install_hint actionlint actionlint "" github.com/rhysd/actionlint/cmd/actionlint ""; missing=1; }
check_tool wrkflw --version            || { install_hint wrkflw wrkflw wrkflw "" "";                                                                       missing=1; }
check_tool zizmor --version            || { install_hint zizmor zizmor zizmor "" zizmor;                                                                   missing=1; }
check_tool pinact --version            || { install_hint pinact pinact "" github.com/suzuki-shunsuke/pinact/cmd/pinact "";                            missing=1; }
check_tool jq --version                || { install_hint jq jq "" "" "";                                                                                   missing=1; }

echo
echo "Full log: $TMP_FILE"

# Deliberate deviation from the general wrapper contract: other wrapper
# scripts (see scripts/lint.sh) exit 0 unless the underlying tool itself
# failed to run, never for findings. doctor.sh's whole job is a presence
# check, so a missing tool is the finding and must surface as exit 1.
exit "$missing"

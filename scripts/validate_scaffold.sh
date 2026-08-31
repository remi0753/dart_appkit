#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}

required_paths=(
  LICENSE
  THIRD_PARTY_NOTICES.md
  licenses/DART_SDK_LICENSE
  ROADMAP.md
  docs/WORKLOG.md
  docs/VERIFICATION.md
  docs/ARCHITECTURE.md
  docs/C_ABI.md
  docs/BUILDING_DART_ENGINE.md
  native/bridge/include/dart_appkit.h
  native/runner/README.md
  packages/dart_appkit/pubspec.yaml
  packages/dart_appkit/lib/dart_appkit.dart
  packages/dart_appkit/lib/src/tool/launcher.dart
  examples/hello_window/pubspec.yaml
  examples/hello_window/bin/main.dart
  scripts/bootstrap_dart_engine.sh
  scripts/check_dart_engine.sh
  scripts/dart_engine_env.sh
  scripts/test_runner_shell.sh
)

for relative_path in ${required_paths[@]}; do
  if [[ ! -f "${project_root}/${relative_path}" ]]; then
    print -u2 "missing required scaffold file: ${relative_path}"
    exit 1
  fi
done

for script in "${project_root}"/scripts/*.sh; do
  /bin/zsh -n "${script}"
done

print "scaffold validation passed"

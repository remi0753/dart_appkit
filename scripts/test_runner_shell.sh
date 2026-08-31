#!/bin/zsh
set -euo pipefail

fail() {
  print -u2 "Runner shell test failed: $1"
  exit 1
}

[[ $# -eq 1 ]] || fail "expected the test Runner path"
runner=$1
[[ -x "${runner}" ]] || fail "Runner is not executable: ${runner}"

set +e
usage_output=$("${runner}" 2>&1)
usage_status=$?
set -e
[[ ${usage_status} -eq 64 ]] || fail "usage exit was ${usage_status}, expected 64"
[[ "${usage_output}" == *"--kernel is required"* ]] || \
  fail "usage error did not name the missing Kernel option"

missing_kernel="${runner}.intentionally-missing.dill"
[[ ! -e "${missing_kernel}" ]] || fail "reserved missing-Kernel path exists"
set +e
input_output=$("${runner}" \
  --kernel "${missing_kernel}" \
  --sdk-version 3.13.2 \
  --sdk-revision shell-test 2>&1)
input_status=$?
set -e
[[ ${input_status} -eq 66 ]] || fail "input exit was ${input_status}, expected 66"
[[ "${input_output}" == *"Kernel file does not exist"* ]] || \
  fail "input error did not name the missing Kernel"

print "Runner shell usage/input tests passed"

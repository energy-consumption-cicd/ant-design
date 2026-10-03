#!/usr/bin/env bash

# Literal transcription of the two measured jobs of .github/workflows/test.yml
# at 9b51721b74269da7ea54a568676f049ebfadb839: build is `build` (:144), test is
# `test-react-latest` (:59) with its two shards run in sequence (D-6).

# GitHub runs every `run:` block under `bash -e`.
set -euo pipefail
STAGE="${1:?stage required: build | test}"

cd /workspace

# Every stage runs all of its commands and exits with the first non-zero code,
# as the vision commands.sh does, so one failing command never truncates the
# workload of the others.
STAGE_EXIT=0
run_step() {
  local label="$1"; shift
  local rc
  echo "=== ${label}: start $(date -u +%FT%TZ) ==="
  set +e
  "$@"
  rc=$?
  set -e
  echo "=== ${label}: end $(date -u +%FT%TZ) exit=${rc} ==="
  if [ "$rc" -ne 0 ] && [ "$STAGE_EXIT" -eq 0 ]; then
    STAGE_EXIT="$rc"
  fi
  return 0
}

# Stands in for `npm run ut-install-react-18`, the first half of the `dist`
# script. utoo 1.0.30 has no offline mode, so under --network none the literal
# command fails with exit 11 and `&&` skips the whole webpack build; the trio it
# would install is baked into the image and swapped in here instead (D-5). It
# has to run between predist and antd-tools, which is where package.json puts
# it: swapping before predist changes dist/antd.css and ten .d.ts files.
install_react_18() {
  rm -rf node_modules/react node_modules/react-dom node_modules/scheduler
  cp -a /opt/react18/react node_modules/react
  cp -a /opt/react18/react-dom node_modules/react-dom
  cp -a /opt/react18/package.json package.json
  node -p '"react " + require("react/package.json").version'
}

case "$STAGE" in

  build)
    # :163-164 compile; the tag sets no heap size and the default V8 heap runs out on the bench,
    # so the step gets the value the HEAD passes to the same command.
    run_step "ut compile" env NODE_OPTIONS=--max_old_space_size=4096 ut compile

    # :172-177 dist, expanded so the registry step can be replaced (D-5).
    # `predist` is an npm hook and still resolves react 19, as upstream does.
    run_step "npm run predist" \
      env NODE_OPTIONS=--max_old_space_size=4096 CI=1 npm run predist
    run_step "install react 18 (D-5)" install_react_18
    run_step "antd-tools run dist" \
      env NODE_OPTIONS=--max_old_space_size=4096 CI=1 npx --no-install antd-tools run dist

    # :179-180 check build files
    run_step "ut test:dekko" ut test:dekko
    ;;

  test)
    # :73, both matrix shards in sequence in this container (D-6). The stage
    # starts from the image tree, which resolves react 19, as test-react-latest
    # does; test-react-legacy, which runs on react 18, is outside the cell.
    node -p '"react " + require("react/package.json").version'

    run_step "ut test shard 1/2" ut test -- --maxWorkers=2 --shard=1/2 --coverage
    run_step "ut test shard 2/2" ut test -- --maxWorkers=2 --shard=2/2 --coverage
    ;;

  *)
    echo "unknown stage: $STAGE" >&2
    exit 2
    ;;

esac

echo "=== stage ${STAGE}: aggregate exit=${STAGE_EXIT} ==="
exit "$STAGE_EXIT"

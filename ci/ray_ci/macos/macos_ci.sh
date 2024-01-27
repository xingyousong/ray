#!/bin/bash

set -ex

export CI="true"
export PYTHON="3.8"
export RAY_USE_RANDOM_PORTS="1"
export RAY_DEFAULT_BUILD="1"
export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"
export BUILD="1"
export DL="1"

filter_flaky_tests() {
  test_targets=""
  while read -r line; do
    test_targets+="$line\n"
  done
  # shellcheck disable=SC2086
  echo $test_targets | bazel run ci/ray_ci/automation:filter_tests -- "flaky"
}

run_small_test() {
  filtered_test_targets=$(bazel query 'attr(tags, "client_tests|small_size_python_tests", tests(//python/ray/tests/...))' | filter_flaky_tests)
  # shellcheck disable=SC2046,SC2086
  bazel test $filtered_test_targets $(./ci/run/bazel_export_options) --config=ci \
    --test_env=CONDA_EXE --test_env=CONDA_PYTHON_EXE --test_env=CONDA_SHLVL --test_env=CONDA_PREFIX \
    --test_env=CONDA_DEFAULT_ENV --test_env=CONDA_PROMPT_MODIFIER --test_env=CI
}

run_medium_a_j_test() {
  filtered_test_targets=$(bazel query 'attr(tags, "kubernetes|medium_size_python_tests_a_to_j", tests(//python/ray/tests/...))' | filter_flaky_tests)
  # shellcheck disable=SC2046,SC2086
  bazel test $filtered_test_targets --config=ci $(./ci/run/bazel_export_options) \
    --test_env=CI
}

run_medium_k_z_test() {
  filtered_test_targets=$(bazel query 'attr(tags, "kubernetes|medium_size_python_tests_k_to_z", tests(//python/ray/tests/...))' | filter_flaky_tests)
  # shellcheck disable=SC2046,SC2086
  bazel test $filtered_test_targets --config=ci $(./ci/run/bazel_export_options) \
    --test_env=CI
}

run_large_test() {
  filtered_test_targets=$(bazel query 'attr(tags, "large_size_python_tests_shard_'"${BUILDKITE_PARALLEL_JOB}"'", tests(//python/ray/tests/...))' | filter_flaky_tests)
  # shellcheck disable=SC2046,SC2086
  bazel test $filtered_test_targets --config=ci $(./ci/run/bazel_export_options) \
    --test_env=CONDA_EXE --test_env=CONDA_PYTHON_EXE --test_env=CONDA_SHLVL --test_env=CONDA_PREFIX --test_env=CONDA_DEFAULT_ENV \
    --test_env=CONDA_PROMPT_MODIFIER --test_env=CI "$@"
}

run_core_dashboard_test() {
  TORCH_VERSION=1.9.0 ./ci/env/install-dependencies.sh
  # Use --dynamic_mode=off until MacOS CI runs on Big Sur or newer. Otherwise there are problems with running tests
  # with dynamic linking.
  # shellcheck disable=SC2046
  bazel test --config=ci --dynamic_mode=off \
    --test_env=CI $(./ci/run/bazel_export_options) --build_tests_only \
    --test_tag_filters=-post_wheel_build -- \
    //:all python/ray/dashboard/... -python/ray/serve/... -rllib/... -core_worker_test
}

run_ray_cpp_and_java() {
  # clang-format is needed by java/test.sh
  pip install clang-format==12.0.1
  ./java/test.sh
  ./ci/ci.sh test_cpp
}

_prelude() {
  rm -rf /tmp/bazel_event_logs
  (which bazel && bazel clean) || true;
  . ./ci/ci.sh init && source ~/.zshenv
  source ~/.zshrc
  ./ci/ci.sh build
  ./ci/env/env_info.sh
}

_epilogue() {
  # Upload test results
  ./ci/build/upload_build_info.sh
  # Assign all macos tests to core for now
  bazel run //ci/ray_ci/automation:test_db_bot -- core /tmp/bazel_event_logs
  # Persist ray logs
  mkdir -p /tmp/artifacts/.ray/
  tar -czf /tmp/artifacts/.ray/logs.tgz /tmp/ray
  # Cleanup runtime environment to save storage
  rm -rf /tmp/ray
  # Cleanup local caches - this should not clean up global disk cache
  bazel clean
}
trap _epilogue EXIT

_prelude
"$@"
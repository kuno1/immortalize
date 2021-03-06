#!/usr/bin/env bats

result () {
  >&3 cat work/time
  # Floor the time
  awk '{split($0,a,"."); print a[1]}' < work/time
}

time_cmd=

measure () {
  if [ "$time_cmd" == '' ]; then
    if [ -f /usr/bin/time ]; then
      time_cmd=/usr/bin/time
    elif [ -f work/cache/time ]; then
      time_cmd=work/cache/time
    else
      >&3 echo 'Error: time command does not exist.'
      exit 1
    fi
  fi

  # Measure immortalize and redirect stdout/stderr to file descriptor 3.
  # Details:
  # https://github.com/bats-core/bats-core#file-descriptor-3-read-this-if-bats-hangs
  "$time_cmd" --quiet -f '%e' -o work/time ./work/immortalize "$@" >&3 2>&1 &
  # Store time's PID
  echo "$!" > work/pid
}

sigterm () {
  # Send SIGTERM to immortalize by using time's PID
  pkill -P "$(< work/pid)"
}

wait_exit () {
  set +e
  wait "$(< work/pid)"
  code="$?"
  set -e
  >&3 echo "Exited with exit code $code."
  return "$code"
}

assert_exit_with_nonzero () {
  if wait_exit; then
    exit 1
  fi
}

assert_exit_with_0 () {
  if ! wait_exit; then
    exit 1
  fi
}

# * `COM`: Command exited
# * `MAX`: Maximum lifetime exceeded
# * `MIN`: Minimum lifetime exceeded
# * `SIG`: SIGTERM received
#
# MIN -> COM -> MAX -> SIG
# MIN -> COM -> SIG -> MAX
@test "MIN -> COM (0)" {
  measure -min-lifetime 2 -command test-bin/command-zero
  assert_exit_with_0
  [ "$(result)" == 4 ]
}

@test "MIN -> COM (1)" {
  measure -min-lifetime 2 -command test-bin/command-one
  assert_exit_with_nonzero
  [ "$(result)" == 4 ]
}

# COM -> MIN -> MAX -> SIG
# COM -> MIN -> SIG -> MAX
# COM -> SIG -> MIN -> MAX
@test "COM (0)" {
  measure -min-lifetime 6 -command test-bin/command-zero
  assert_exit_with_0
  [ "$(result)" == 4 ]
}

@test "COM (1)" {
  measure -min-lifetime 6 -command test-bin/command-one
  assert_exit_with_nonzero
  [ "$(result)" == 4 ]
}

# MIN -> MAX -> COM -> SIG
# MIN -> MAX -> SIG -> COM
@test "MIN -> MAX (0)" {
  measure -max-lifetime 2 -command test-bin/command-zero
  assert_exit_with_0
  [ "$(result)" == 2 ]
}

@test "MIN -> MAX (1)" {
  measure -max-lifetime 2 -command test-bin/command-one
  assert_exit_with_nonzero
  [ "$(result)" == 2 ]
}

# SIG -> MIN -> MAX -> COM
# SIG -> MIN -> COM -> MAX
@test "SIG -> MIN (0)" {
  measure -min-lifetime 2 -command test-bin/command-zero
  sleep 1
  sigterm
  assert_exit_with_0
  [ "$(result)" == 2 ]
}

@test "SIG -> MIN (1)" {
  measure -min-lifetime 2 -command test-bin/command-one
  sleep 1
  sigterm
  assert_exit_with_nonzero
  [ "$(result)" == 2 ]
}

# MIN -> SIG -> COM -> MAX
# MIN -> SIG -> MAX -> COM
@test "MIN -> SIG (0)" {
  measure -min-lifetime 2 -command test-bin/command-zero
  sleep 3
  sigterm
  assert_exit_with_0
  [ "$(result)" == 3 ]
}

@test "MIN -> SIG (1)" {
  measure -min-lifetime 2 -command test-bin/command-one
  sleep 3
  sigterm
  assert_exit_with_nonzero
  [ "$(result)" == 3 ]
}

# SIG -> COM -> MIN -> MAX
@test "SIG -> COM (0)" {
  measure -min-lifetime 6 -command test-bin/command-zero
  sleep 2
  sigterm
  assert_exit_with_0
  [ "$(result)" == 4 ]
}

@test "SIG -> COM (1)" {
  measure -min-lifetime 6 -command test-bin/command-one
  sleep 2
  sigterm
  assert_exit_with_nonzero
  [ "$(result)" == 4 ]
}

# Invalid order
@test "MAX -> MIN" {
  measure -min-lifetime 4 -max-lifetime 2 -command test-bin/command-zero
  assert_exit_with_nonzero
  [ "$(result)" == 0 ]
}

@test "Log path" {
  log=work/immortalize.log
  rm -f "$log"
  ./work/immortalize \
    -max-lifetime 2 \
    -command test-bin/command-zero \
    -log-path "$log" >&3 2>&1

  [ 1 -lt "$(wc -l < "$log")" ]
}

@test "log level - default (info)" {
  log=work/immortalize.log
  rm -f "$log"
  ./work/immortalize \
    -max-lifetime 2 \
    -command test-bin/command-zero \
    -log-path "$log" >&3 2>&1

  [ 1 -lt "$(grep info < "$log" | wc -l)" ]
  [ 0 -eq "$(grep debug < "$log" | wc -l)" ]
}

@test "log level - debug" {
  log=work/immortalize.log
  rm -f "$log"
  ./work/immortalize \
    -max-lifetime 2 \
    -command test-bin/command-zero \
    -log-path "$log" \
    -log-level debug >&3 2>&1

  [ 1 -lt "$(grep info < "$log" | wc -l)" ]
  [ 0 -lt "$(grep debug < "$log" | wc -l)" ]
}

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

# * `COM`: Command exited
# * `MAX`: Maximum lifetime exceeded
# * `MIN`: Minimum lifetime exceeded
# * `SIG`: SIGTERM received
#
# MIN -> COM -> MAX -> SIG
# MIN -> COM -> SIG -> MAX
@test "MIN -> COM" {
  measure -min-lifetime 2 -command test-bin/command-zero
  wait_exit
  [ "$(result)" == 4 ]
}

# COM -> MIN -> MAX -> SIG
# COM -> MIN -> SIG -> MAX
# COM -> SIG -> MIN -> MAX
@test "COM" {
  measure -min-lifetime 6 -command test-bin/command-zero
  wait_exit
  [ "$(result)" == 4 ]
}

# MIN -> MAX -> COM -> SIG
# MIN -> MAX -> SIG -> COM
@test "MIN -> MAX" {
  measure -max-lifetime 2 -command test-bin/command-zero
  wait
  [ "$(result)" == 2 ]
}

# SIG -> MIN -> MAX -> COM
# SIG -> MIN -> COM -> MAX
@test "SIG -> MIN" {
  measure -min-lifetime 2 -command test-bin/command-zero
  sleep 1
  sigterm
  wait
  [ "$(result)" == 2 ]
}

# MIN -> SIG -> COM -> MAX
# MIN -> SIG -> MAX -> COM
@test "MIN -> SIG" {
  measure -min-lifetime 2 -command test-bin/command-zero
  sleep 3
  sigterm
  wait
  [ "$(result)" == 3 ]
}

# SIG -> COM -> MIN -> MAX
@test "SIG -> COM" {
  measure -min-lifetime 6 -command test-bin/command-zero
  sleep 2
  sigterm
  wait
  [ "$(result)" == 4 ]
}

# Invalid order
@test "MAX -> MIN" {
  measure -min-lifetime 4 -max-lifetime 2 -command test-bin/command-zero
  if wait_exit; then
    exit 1
  fi
  [ "$(result)" == 0 ]
}

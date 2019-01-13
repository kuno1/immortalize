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
  "$time_cmd" -f '%e' -o work/time ./work/immortalize "$@" >&3 2>&1 &
  # Store time's PID
  echo "$!" > work/pid
}

sigterm () {
  # Send SIGTERM to immortalize by using time's PID
  pkill -P "$(< work/pid)"
}

# MIN -> COM
@test "MIN -> COM" {
  measure -min-lifetime 2 -command test-bin/command-zero
  wait
  [ "$(result)" == 4 ]
}

# COM -> MIN
@test "COM -> MIN" {
  measure -min-lifetime 6 -command test-bin/command-zero
  wait
  [ "$(result)" == 4 ]
}

# SIG -> MIN
@test "SIG -> MIN" {
  measure -min-lifetime 2 -command test-bin/command-zero
  sleep 1
  sigterm
  wait
  [ "$(result)" == 2 ]
}

# MIN -> SIG
@test "MIN -> SIG" {
  measure -min-lifetime 2 -command test-bin/command-zero
  sleep 3
  sigterm
  wait
  [ "$(result)" == 3 ]
}

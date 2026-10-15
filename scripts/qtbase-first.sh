#!/bin/sh
# Compiler launcher for building FCEUX: usage qtbase-first.sh <compiler> <args...>
# FCEUX builds against Homebrew's qtbase, but another linked Qt's headers sit in /opt/homebrew/include,
# which SDL2 adds ahead of qtbase. This moves /opt/homebrew/include to the very end of the search.
compiler="$1"
shift
after_isystem=0
for arg do
  shift
  if [ "$after_isystem" = 1 ]; then
    after_isystem=0
    [ "$arg" = /opt/homebrew/include ] || set -- "$@" -isystem "$arg"
    continue
  fi
  case "$arg" in
    -I/opt/homebrew/include) ;;
    -isystem) after_isystem=1 ;;
    *) set -- "$@" "$arg" ;;
  esac
done
exec "$compiler" "$@" -idirafter /opt/homebrew/include

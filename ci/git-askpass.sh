#!/bin/sh

case "$1" in
  *Username*) printf '%s\n' "$GITHUB_AUTH_USER" ;;
  *Password*) printf '%s\n' "$GITHUB_TOKEN" ;;
  *) exit 1 ;;
esac

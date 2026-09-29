#!/bin/sh

case "$1" in
  *Username*) printf '%s\n' "$GIT_USER_NAME" ;;
  *Password*) printf '%s\n' "$GITHUB_TOKEN" ;;
  *) exit 1 ;;
esac

#!/usr/bin/env bash
# Run a command; on failure show the end of its output as an annotation
# (annotations can be read without signing in, job logs can not).
log=$(mktemp)
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
    tail -n 60 "$log" | cut -c1-300 | sed -e 's/%/%25/g' -e 's/\r//g' | awk 'BEGIN{ORS="%0A"} {print}' \
        | sed -e 's/^/::error title=failed: '"$1"'::/'
    echo
fi
exit "$status"

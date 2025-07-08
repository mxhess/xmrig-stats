#!/bin/bash
# Query systemd journal for the latest "new job" entry from xmrig-proxy to identify the active pool

journalctl -u xmrig-proxy -q --since "1 hour ago" --no-pager | grep "new job from" | tail -n 1 | awk -F'new job from ' '{print $2}' | awk '{print $1}'


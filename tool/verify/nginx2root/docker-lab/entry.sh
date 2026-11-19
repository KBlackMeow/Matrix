#!/bin/sh
iptables -A OUTPUT -p tcp --dport 9000 -j DROP 2>/dev/null || true
exec nginx -g "daemon off;"

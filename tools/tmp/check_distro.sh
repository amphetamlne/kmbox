#!/bin/bash
cat /etc/os-release 2>/dev/null | head -5
echo "---"
if which apt >/dev/null 2>&1; then echo "apt: available"; else echo "apt: NOT available"; fi
if which apt-get >/dev/null 2>&1; then echo "apt-get: available"; else echo "apt-get: NOT available"; fi
echo "---"
echo "Architecture: $(uname -m)"
echo "User: $(whoami)"

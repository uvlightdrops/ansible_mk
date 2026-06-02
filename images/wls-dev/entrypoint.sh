#!/bin/sh
set -eu

# generate host keys if missing
ssh-keygen -A || true

# best-effort fix ownerships for /home/docker and /home/weblogic
chown -R docker:docker /home/docker || true
chown -R weblogic:weblogic /home/weblogic || true

# ensure .ssh exists and permissions are sane
mkdir -p /home/docker/.ssh
chmod 700 /home/docker/.ssh || true
[ -f /home/docker/.ssh/authorized_keys ] && chmod 600 /home/docker/.ssh/authorized_keys || true

# start sshd in background
/usr/sbin/sshd

# execute given command
exec "$@"


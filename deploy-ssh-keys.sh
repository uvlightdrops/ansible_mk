#!/usr/bin/env bash
set -euo pipefail

CONTAINER_PREFIX="wlcluster"
#SSH_USER="flow"
SSH_USER="docker"
KEYFILE=id_ed25519.pub
PUBKEY_PATH="${HOME}/.ssh/${KEYFILE}"
echo "PUBKEY_PATH = $PUBKEY_PATH"
DISABLE_PASSWORD_AUTH=true   # true = deaktiviert PasswordAuthentication in sshd_config

if [ ! -f "$PUBKEY_PATH" ]; then
  echo "Public key nicht gefunden: $PUBKEY_PATH"
  exit 1
fi

containers=$(docker ps --format '{{.Names}}' | grep "^${CONTAINER_PREFIX}" || true)
if [ -z "$containers" ]; then
  echo "Keine Minikube-Container gefunden (Prefix=${CONTAINER_PREFIX})."
  exit 1
fi

SSH_HOME=/home/$SSH_USER
echo "Gefundene Container:"
echo "$containers"
echo
for c in $containers; do
  echo "==> Processing $c, cp $PUBKEY_PATH $c:/$SSH_HOME/ansible_id.pub"
  echo "docker exec --privileged -u root $c mkdir -p $SSH_HOME/.ssh"
  echo "docker exec --privileged -u root $c grep docker /etc/passwd"
  docker exec --privileged -u root "$c" mkdir -p $SSH_HOME/.ssh
  docker cp setup_user.sh  "$c:/$SSH_HOME/setup_user.sh"

  echo "docker cp $PUBKEY_PATH $c:/$SSH_HOME/.ssh/$KEYFILE"
  docker cp "$PUBKEY_PATH" "$c:/$SSH_HOME/.ssh/$KEYFILE"

  docker exec --privileged -u root "$c" bash $SSH_HOME/setup_user.sh
	ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c")
	echo "Fertig. Test: ssh -i ${HOME}/.ssh/$KEYFILE ${SSH_USER}@$ip"
  echo
done


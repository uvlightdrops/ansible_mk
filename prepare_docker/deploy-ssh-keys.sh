#!/usr/bin/env bash
set -euo pipefail

CONTAINER_PREFIX="wlcluster"
#SSH_USER="flow"
SSH_USER="docker"
KEYFILE=id_ed25519_docker.pub
PUBKEY_PATH="${HOME}/.ssh/${KEYFILE}"
echo "PUBKEY_PATH = $PUBKEY_PATH"
DISABLE_PASSWORD_AUTH=true   # true = deaktiviert PasswordAuthentication in sshd_config

# Optional: prepare hostPath directories for PVs on each node
PV_PREP=${PV_PREP:-true}
PV_PATH=${PV_PATH:-/mnt/weblogic/pv-home}

if [ ! -f "$PUBKEY_PATH" ]; then
  echo "Public key nicht gefunden: $PUBKEY_PATH"
  exit 1
fi

containers=$(docker ps --format '{{.Names}}' | grep "^${CONTAINER_PREFIX}" || true)
if [ -z "$containers" ]; then
  echo "Keine Minikube-Container gefunden (Prefix=${CONTAINER_PREFIX})."
  exit 1
fi

SSH_HOME="/home/$SSH_USER"
echo "SSH_USER =" $SSH_USER
echo "SSH_HOME =" $SSH_HOME

echo "Gefundene Container:"
echo "$containers"
echo
for c in $containers; do
  echo "==> Processing $c"
  echo "docker exec --privileged -u root $c mkdir -p $SSH_HOME/.ssh"
  echo "docker exec --privileged -u root $c grep docker /etc/passwd"
  docker exec --privileged -u root "$c" mkdir -p $SSH_HOME/.ssh
  if [ "$PV_PREP" = "true" ]; then
    echo "Preparing hostPath for PV on $c: $PV_PATH"
    docker exec --privileged -u root "$c" mkdir -p "$PV_PATH" || true
    echo "docker exec --privileged -u root $c chown -R 1000:1000 $PV_PATH"
    docker exec --privileged -u root "$c" chown -R 1000:1000 "$PV_PATH" || true
    echo "docker exec --privileged -u root $c chmod 700 $PV_PATH"
    docker exec --privileged -u root "$c" chmod 700 "$PV_PATH" || true
  fi
  docker cp prepare_docker/setup_user.sh  "$c:/$SSH_HOME/setup_user.sh"

  echo "docker cp $PUBKEY_PATH $c:/$SSH_HOME/.ssh/$KEYFILE"
  docker cp "$PUBKEY_PATH" "$c:/$SSH_HOME/.ssh/$KEYFILE"

  docker exec --privileged -u root "$c" bash $SSH_HOME/setup_user.sh
	ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c")
	echo "Fertig. Test: ssh -i ${HOME}/.ssh/$KEYFILE ${SSH_USER}@$ip"
  echo
done


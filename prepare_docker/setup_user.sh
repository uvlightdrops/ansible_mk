#!/bin/bash
#
set -e
USER=docker # ${SSH_USER}
echo "Running as root on remote, working on USER = $USER"
#echo SSH_USER = $SSH_USER

apt-get update -y >/dev/null 2>&1 || true
apt-get install -y sudo >/dev/null 2>&1 || true
if ! grep -q "^$USER:" /etc/passwd; then
  echo "User $USER does not exist, creating..."
	useradd -m -s /bin/bash "$USER" || true
fi
echo "$USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$USER" || true

mkdir -p /home/$USER/.ssh
touch /home/$USER/.ssh/authorized_keys

#PUBKEY=/home/$USER/.ssh/ansible_id.pub
PUBKEY=/home/$USER/.ssh/id_ed25519.pub
# append key only if not present
grep -qxFf "$PUBKEY" /home/$USER/.ssh/authorized\_keys 2>/dev/null || cat "$PUBKEY" >> /home/$USER/.ssh/authorized_keys

chown -R "$USER":"$USER" /home/"$USER"/.ssh
chmod 700 /home/"$USER"/.ssh
chmod 600 /home/"$USER"/.ssh/authorized_keys


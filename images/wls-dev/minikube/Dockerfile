FROM wls-dev:base

# Minikube overlay: adds SSH server, host-key setup and sshd entrypoint.
# SSH_PUBKEY can be passed at build time for manual one-off builds;
# at runtime keys are injected via ConfigMap/InitContainer (preferred).

ARG SSH_PUBKEY=""

RUN apt-get update && \
    apt-get install -y openssh-server && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN ssh-keygen -A || true && \
    cp -a /etc/ssh /etc/ssh.orig || true && \
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config || true

EXPOSE 22

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Allow passing a public key at build time so the image can be built with key-based SSH access.
ARG SSH_PUBKEY=""

# Minimal image with OpenJDK and openssh for dev/testing only
# Use OpenJDK 17 on Ubuntu 24.04 by default (adjust if you need a different Java version)
RUN apt-get update && \
    apt-get install -y openjdk-17-jdk openssh-server sudo && \
    # create weblogic and docker users for dev/ansible access
    useradd -m -s /bin/bash weblogic && \
    useradd -m -s /bin/bash docker && \
    mkdir -p /var/run/sshd /home/weblogic/.ssh /home/docker/.ssh && \
    chown -R weblogic:weblogic /home/weblogic && \
    chown -R docker:docker /home/docker && \
    mkdir -p /u01 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN ssh-keygen -A || true && \
    cp -a /etc/ssh /etc/ssh.orig || true

# Do NOT bake pubkeys into the image. Use a ConfigMap or InitContainer to inject
# authorized_keys at runtime. The build-arg SSH_PUBKEY remains for manual one-off
# builds but is intentionally not installed here to avoid embedding credentials.

# Prefer key-based authentication; disable password authentication by default.
RUN sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config || true
EXPOSE 22

# Copy entrypoint and use it to start sshd and run the container command
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# Keep container alive while sshd runs in the background.
# Use 'sleep infinity' so the container does not exit when there is no TTY.
CMD ["sleep", "infinity"]


FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Allow passing a public key at build time so the image can be built with key-based SSH access.
ARG SSH_PUBKEY=""

# Minimal image with OpenJDK and openssh for dev/testing only
# Use OpenJDK 17 on Ubuntu 24.04 by default (adjust if you need a different Java version)
RUN apt-get update && \
    apt-get install -y openjdk-17-jdk openssh-server sudo && \
    useradd -m -s /bin/bash weblogic && \
    mkdir -p /var/run/sshd /home/weblogic/.ssh && \
    chown -R weblogic:weblogic /home/weblogic && \
    mkdir -p /u01 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN ssh-keygen -A || true && \
    cp -a /etc/ssh /etc/ssh.orig || true

# If an SSH public key was provided at build time, install it for the weblogic user.
RUN if [ -n "${SSH_PUBKEY}" ]; then \
      printf '%s\n' "${SSH_PUBKEY}" >> /home/weblogic/.ssh/authorized_keys && \
      chown weblogic:weblogic /home/weblogic/.ssh/authorized_keys && \
      chmod 600 /home/weblogic/.ssh/authorized_keys ; \
    fi

# Prefer key-based authentication; disable password authentication by default.
RUN sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config || true
EXPOSE 22

# Ensure host keys exist at container start (generate missing host keys) and start sshd.
CMD ["/bin/sh", "-c", "ssh-keygen -A || true && exec /usr/sbin/sshd -D"]


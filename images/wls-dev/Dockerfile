FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# Minimal image with OpenJDK and openssh for dev/testing only
RUN apt-get update && \
    apt-get install -y openjdk-11-jdk openssh-server sudo && \
    useradd -m -s /bin/bash weblogic && \
    echo 'weblogic:weblogic' | chpasswd && \
    mkdir -p /var/run/sshd /home/weblogic/.ssh && \
    chown -R weblogic:weblogic /home/weblogic && \
    mkdir -p /u01 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Allow password authentication for quick dev access (not for production)
RUN sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]


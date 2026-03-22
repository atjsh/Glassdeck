FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        neofetch \
        nano \
        netcat-openbsd \
        openssh-server \
        passwd \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /etc/ssh/sshd_config.d /opt/glassdeck-seed/home /var/lib/glassdeck-runtime/hostkeys

COPY fixtures/home/ /opt/glassdeck-seed/home/
COPY ssh/docker-entrypoint.sh /usr/local/bin/glassdeck-ssh-entrypoint

RUN chmod +x /usr/local/bin/glassdeck-ssh-entrypoint \
    && printf '%s\n' \
        'Port 22' \
        'HostKey /var/lib/glassdeck-runtime/hostkeys/ssh_host_ed25519_key' \
        'PasswordAuthentication yes' \
        'PubkeyAuthentication yes' \
        'PermitRootLogin no' \
        'UsePAM yes' \
        'AllowUsers glassdeck' \
        > /etc/ssh/sshd_config.d/glassdeck.conf

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/glassdeck-ssh-entrypoint"]
CMD ["/usr/sbin/sshd", "-D", "-e"]

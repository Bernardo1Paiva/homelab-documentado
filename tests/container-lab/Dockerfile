# Imagem "VM de mentira": Ubuntu 24.04 com systemd, para rodar os MESMOS
# scripts de provision/ em contêineres (testes automáticos e CI).
FROM ubuntu:24.04
ENV container=docker
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus iproute2 iputils-ping ca-certificates curl \
      sudo less nano bsdextrautils \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && systemctl mask getty@tty1.service console-getty.service systemd-udevd.service \
      systemd-modules-load.service sys-kernel-config.mount sys-kernel-debug.mount
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

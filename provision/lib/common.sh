#!/usr/bin/env bash
# =============================================================================
#  lib/common.sh — funções compartilhadas por todos os scripts
# =============================================================================
set -euo pipefail

PROVISION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lab.env
source "${PROVISION_DIR}/lab.env"

export DEBIAN_FRONTEND=noninteractive

log()  { printf '\033[1;34m[%s] %s\033[0m\n' "$(hostname -s)" "$*"; }
ok()   { printf '\033[1;32m[%s] OK: %s\033[0m\n' "$(hostname -s)" "$*"; }
warn() { printf '\033[1;33m[%s] AVISO: %s\033[0m\n' "$(hostname -s)" "$*" >&2; }
die()  { printf '\033[1;31m[%s] ERRO: %s\033[0m\n' "$(hostname -s)" "$*" >&2; exit 1; }

is_container() { [ "${LAB_PLATFORM}" = "container" ]; }

# Espera até um comando dar certo (ex.: serviço subir). Uso: wait_for 60 "descr" cmd args...
wait_for() {
  local timeout="$1" desc="$2"; shift 2
  local i
  for ((i = 0; i < timeout; i++)); do
    if "$@" >/dev/null 2>&1; then ok "${desc}"; return 0; fi
    sleep 1
  done
  die "tempo esgotado esperando: ${desc}"
}

apt_install() {
  log "instalando pacotes: $*"
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends "$@" >/dev/null
}

# Renderiza um template trocando {{VARIAVEL}} pelo valor da variável de ambiente.
render() {
  local src="$1" dst="$2" content var
  content="$(cat "$src")"
  for var in $(grep -o '{{[A-Z0-9_]*}}' "$src" | sort -u | tr -d '{}'); do
    content="${content//\{\{${var}\}\}/${!var}}"
  done
  printf '%s\n' "$content" > "$dst"
}

# Grava /etc/resolv.conf mesmo quando ele é um link (VM) ou um bind mount (contêiner).
write_resolv_conf() {
  local ns="$1"
  if [ -L /etc/resolv.conf ]; then rm -f /etc/resolv.conf; fi
  printf 'nameserver %s\nsearch %s\n' "$ns" "$LAB_DOMAIN" > /etc/resolv.conf
}

# --- Passos comuns a todas as máquinas --------------------------------------
# Uso: base_setup <hostname> <ip|dhcp> "<serviços críticos desta máquina>"
# Os serviços críticos são os que o monitoramento vigia (alerta ServicoParado).
base_setup() {
  local name="$1" ip="$2"
  MONITORED_UNITS="${3:-}"
  log "configuração base de ${name}"

  hostnamectl set-hostname "${name}" 2>/dev/null || hostname "${name}"
  echo "${name}" > /etc/hostname
  ln -sf "/usr/share/zoneinfo/${TZ_NAME}" /etc/localtime

  # /etc/hosts: o próprio nome resolve para o IP da rede corporativa
  # (reescreve no lugar em vez de "sed -i": no contêiner o arquivo é montado)
  local hosts_new
  hosts_new="$(grep -vE "[[:space:]]${name}(\.${LAB_DOMAIN})?([[:space:]]|$)" /etc/hosts || true)"
  if [ "${ip}" != "dhcp" ]; then
    hosts_new="${hosts_new}"$'\n'"${ip} ${name}.${LAB_DOMAIN} ${name}"
  fi
  printf '%s\n' "${hosts_new}" > /etc/hosts

  apt_install prometheus-node-exporter dnsutils iproute2 iputils-ping curl \
              ca-certificates chrony

  configure_network "${ip}"
  configure_node_exporter
  configure_time_client
}

# Placa da rede corporativa: casada pelo MAC (definido no Vagrantfile).
# Servidores com IP fixo; estação via DHCP.
configure_network() {
  local ip="$1"
  if is_container; then
    log "contêiner: rede gerenciada pelo harness, pulando netplan"
    return 0
  fi
  local mac="${LAN_MAC:?LAN_MAC não definido pelo Vagrantfile}"
  find_lan_if "${mac}"
  log "configurando ${LAN_IF} (${mac}) via netplan"
  if [ "${ip}" = "dhcp" ]; then
    cat > /etc/netplan/60-corp-lan.yaml <<EOF
network:
  version: 2
  ethernets:
    corp-lan:
      match: { macaddress: "${mac}" }
      dhcp4: true
      # rota padrão continua pelo NAT do VirtualBox; DNS e domínio vêm do dc01
      dhcp4-overrides: { use-routes: false, use-domains: true }
EOF
  else
    local dns_list="[${DC01_IP}]"
    [ "${ip}" = "${DC01_IP}" ] && dns_list="[127.0.0.1]"
    cat > /etc/netplan/60-corp-lan.yaml <<EOF
network:
  version: 2
  ethernets:
    corp-lan:
      match: { macaddress: "${mac}" }
      dhcp4: false
      addresses: [${ip}/${LAB_NETMASK_BITS}]
      nameservers:
        addresses: ${dns_list}
        search: [${LAB_DOMAIN}]
EOF
  fi
  chmod 600 /etc/netplan/60-corp-lan.yaml
  netplan apply
}

# Descobre o nome real da placa (ex.: enp0s8) a partir do MAC fixado no
# Vagrantfile e guarda em LAN_IF, usado depois pelo Kea e pelo Samba.
find_lan_if() {
  local mac="${1,,}"
  LAN_IF="$(ip -o link | awk -v m="${mac}" 'tolower($0) ~ m { sub(":", "", $2); print $2; exit }')"
  [ -n "${LAN_IF}" ] || die "nenhuma placa com MAC ${mac} (confira o Vagrantfile)"
  export LAN_IF
}

configure_node_exporter() {
  # Coletor systemd: só os serviços críticos DESTA máquina, para alertar
  # quando um deles para (e não alertar por serviço que nem deveria rodar aqui).
  local units="${MONITORED_UNITS}" args=""
  is_container || units="${units:+${units} }chrony"
  if [ -n "${units}" ]; then
    args="--collector.systemd --collector.systemd.unit-include=($(echo "${units}" | tr ' ' '|'))\\.service"
  fi
  # No contêiner de teste, ignora arquivos montados do host (/etc/hosts etc.)
  if is_container; then
    args="${args} --collector.filesystem.mount-points-exclude=^/(dev|proc|run|sys|etc|opt/homelab-src)(\$|/)"
  fi
  printf 'ARGS="%s"\n' "${args# }" > /etc/default/prometheus-node-exporter
  systemctl enable prometheus-node-exporter >/dev/null 2>&1
  systemctl restart prometheus-node-exporter
}

configure_time_client() {
  # Kerberos tolera no máximo 5 min de diferença de relógio: todos sincronizam
  # com o dc01. Em contêiner o relógio é do host, então não mexemos.
  if is_container; then systemctl disable --now chrony >/dev/null 2>&1 || true; return 0; fi
  if [ "$(hostname -s)" != "dc01" ]; then
    cat > /etc/chrony/sources.d/corp-lab.sources <<EOF
server ${DC01_IP} iburst prefer
EOF
    systemctl restart chrony
  fi
}

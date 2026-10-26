#!/usr/bin/env bash
# =============================================================================
#  mon01.sh — Monitoramento do homelab
#  Papéis: Prometheus (coleta + regras), Blackbox Exporter (testes de fora),
#          Alertmanager (entrega dos alertas)
#  Passo a passo manual equivalente: docs/runbooks/RB-06-monitoramento.md
# =============================================================================
source "$(dirname "$0")/lib/common.sh"

base_setup mon01 "${MON01_IP}" "prometheus prometheus-alertmanager prometheus-blackbox-exporter"
apt_install prometheus prometheus-alertmanager prometheus-blackbox-exporter jq bsdextrautils

# Comandos de apoio para o técnico: "alertas" e "alvos"
install -m 755 "${PROVISION_DIR}/files/bin/alertas" /usr/local/bin/alertas
install -m 755 "${PROVISION_DIR}/files/bin/alvos"   /usr/local/bin/alvos

if is_container; then write_resolv_conf "${DC01_IP}"; fi

# --- Configurações (templates do repositório) --------------------------------
mkdir -p /etc/prometheus/rules
render "${PROVISION_DIR}/files/prometheus.yml.tpl" /etc/prometheus/prometheus.yml
render "${PROVISION_DIR}/files/blackbox.yml.tpl"   /etc/prometheus/blackbox.yml
cp "${PROVISION_DIR}/files/alertas.yml"            /etc/prometheus/rules/alertas.yml
cp "${PROVISION_DIR}/files/alertmanager.yml"       /etc/prometheus/alertmanager.yml

# Valida antes de aplicar: configuração quebrada = monitoramento cego
promtool check config /etc/prometheus/prometheus.yml >/dev/null || die "prometheus.yml inválido"
promtool check rules  /etc/prometheus/rules/alertas.yml >/dev/null || die "regras de alerta inválidas"
amtool check-config   /etc/prometheus/alertmanager.yml >/dev/null || die "alertmanager.yml inválido"

# Retenção de 15 dias é suficiente para o laboratório
echo 'ARGS="--storage.tsdb.retention.time=15d --web.enable-lifecycle"' > /etc/default/prometheus

# O ping (ICMP) precisa de socket "raw": damos só essa permissão ao exporter
mkdir -p /etc/systemd/system/prometheus-blackbox-exporter.service.d
cat > /etc/systemd/system/prometheus-blackbox-exporter.service.d/icmp.conf <<'EOF'
[Service]
AmbientCapabilities=CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_RAW
EOF
systemctl daemon-reload

for svc in prometheus-blackbox-exporter prometheus-alertmanager prometheus; do
  systemctl enable "${svc}" >/dev/null 2>&1
  systemctl restart "${svc}"
done

wait_for 60 "Prometheus no ar"   curl -sf http://localhost:9090/-/ready
wait_for 60 "Alertmanager no ar" curl -sf http://localhost:9093/-/ready
wait_for 30 "Blackbox no ar"     curl -sf http://localhost:9115/

ok "mon01 pronto: Prometheus :9090, Alertmanager :9093, Blackbox :9115"

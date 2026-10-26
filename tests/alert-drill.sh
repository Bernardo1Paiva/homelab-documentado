#!/usr/bin/env bash
# =============================================================================
#  alert-drill.sh — simulação de incidente: "o DHCP caiu, o monitoramento viu?"
#  Para o Kea no dc01, espera o alerta ServicoParado disparar, religa o serviço
#  e espera o alerta se resolver. Prova que o monitoramento funciona de ponta
#  a ponta (coleta → regra → Alertmanager).
#
#  Roda na sua máquina (Git Bash no Windows), na pasta do repositório:
#    bash tests/alert-drill.sh                 # usa "vagrant ssh"
#  O harness de contêineres usa: EXEC="docker exec" ...
# =============================================================================
set -euo pipefail
EXEC="${EXEC:-vagrant}"

run_on() { # host comando  (via vagrant, o comando vai em base64 por causa das aspas)
  if [ "${EXEC}" = "vagrant" ]; then
    vagrant ssh "$1" -c "echo $(printf '%s' "$2" | base64 -w0) | base64 -d | sudo bash" 2>/dev/null | tr -d '\r'
  else ${EXEC} "${PREFIX:-}$1" bash -c "$2"; fi
}
alert_state() { # devolve FIRING | PENDING | (vazio)
  run_on mon01 "alertas" | awk '$2=="ServicoParado" && $4 ~ /kea-dhcp4-server/ {print $1; exit}' || true
}
am_has_alert() {
  run_on mon01 "curl -s localhost:9093/api/v2/alerts" | grep -q '"alertname":"ServicoParado"'
}
ts() { date '+%H:%M:%S'; }

echo "[$(ts)] Simulação: parando o DHCP (kea-dhcp4-server) no dc01"
run_on dc01 "systemctl stop kea-dhcp4-server"
START=$(date +%s)

for _ in $(seq 1 30); do
  st="$(alert_state)"
  [ -n "$st" ] && echo "[$(ts)] alerta ServicoParado: ${st}"
  [ "$st" = "FIRING" ] && break
  sleep 5
done
[ "$st" = "FIRING" ] || { echo "FALHOU: o alerta não disparou"; run_on dc01 "systemctl start kea-dhcp4-server"; exit 1; }
echo "[$(ts)] alerta DISPARADO $(( $(date +%s) - START ))s depois da queda"

sleep 5
if am_has_alert; then echo "[$(ts)] Alertmanager recebeu o alerta (seria enviado à equipe)"
else echo "FALHOU: Alertmanager não recebeu"; run_on dc01 "systemctl start kea-dhcp4-server"; exit 1; fi

echo "[$(ts)] Correção (runbook TS-05): religando o serviço"
run_on dc01 "systemctl start kea-dhcp4-server"
for _ in $(seq 1 30); do
  st="$(alert_state)"
  [ -z "$st" ] && break
  sleep 5
done
[ -z "$st" ] || { echo "FALHOU: alerta não se resolveu"; exit 1; }
echo "[$(ts)] alerta RESOLVIDO — serviço de volta, tempo total $(( $(date +%s) - START ))s"
echo "Simulação concluída com sucesso."

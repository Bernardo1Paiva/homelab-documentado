#!/usr/bin/env bash
# =============================================================================
#  run-lab.sh — sobe o homelab em contêineres para TESTE AUTOMÁTICO
#
#  Não substitui o laboratório em VMs (Vagrantfile): serve para validar os
#  scripts de provision/ rapidamente, em qualquer Linux com Docker, e no CI.
#  Diferenças em relação às VMs: a rede de cada contêiner é dada pelo Docker
#  (não pelo netplan) e o relógio é o do host (sem chrony).
#
#  Uso:  tests/container-lab/run-lab.sh up | test | drill | backup | evidence | down | all
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
source "${REPO}/provision/lab.env"

NET="homelab-net"
IMG="homelab/noble-systemd:latest"
PREFIX="hl-"
EVID="${EVID_DIR:-${REPO}/docs/evidencias}"
declare -A IPS=( [dc01]="${DC01_IP}" [fs01]="${FS01_IP}" [mon01]="${MON01_IP}" [ws01]="${LAB_NET_PREFIX}.90" )
ORDER=(dc01 fs01 mon01 ws01)
ENVS=(-e LAB_PLATFORM=container -e LAN_IF=eth0 -e DNS_FORWARDER=127.0.0.11)

cgroup_opts() {
  if [ "$(stat -fc %T /sys/fs/cgroup)" = "cgroup2fs" ]; then
    echo "--cgroupns=private"
  else
    echo "--cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw"
  fi
}

up() {
  docker build -q -t "${IMG}" "${HERE}" >/dev/null
  docker network inspect "${NET}" >/dev/null 2>&1 || \
    docker network create --subnet "${LAB_NET_CIDR}" --gateway "${LAB_NET_PREFIX}.1" "${NET}" >/dev/null
  for n in "${ORDER[@]}"; do
    docker rm -f "${PREFIX}${n}" >/dev/null 2>&1 || true
    # shellcheck disable=SC2046
    docker run -d --name "${PREFIX}${n}" --hostname "${n}" \
      --network "${NET}" --ip "${IPS[$n]}" \
      --privileged $(cgroup_opts) --tmpfs /run --tmpfs /run/lock --tmpfs /tmp:exec \
      -v "${REPO}:/opt/homelab-src:ro" "${IMG}" >/dev/null
  done
  for n in "${ORDER[@]}"; do
    echo "=================== provisionando ${n} ==================="
    docker exec "${ENVS[@]}" "${PREFIX}${n}" bash -c \
      "mkdir -p /opt/homelab && cp -r /opt/homelab-src/provision /opt/homelab-src/tests /opt/homelab/ \
       && bash /opt/homelab/provision/${n}.sh"
  done
}

run_test() {
  set +e   # roda todos os testes mesmo se algum falhar
  mkdir -p "${EVID}"
  echo "aguardando o Prometheus coletar os alvos (45s)..."; sleep 45
  docker exec "${ENVS[@]}" "${PREFIX}ws01" bash /opt/homelab/tests/smoke-test.sh 2>&1 | tee "${EVID}/smoke-test.log"
  local rc1=${PIPESTATUS[0]}
  docker exec "${ENVS[@]}" "${PREFIX}dc01" bash /opt/homelab/tests/dc-checks.sh 2>&1 | tee "${EVID}/dc-checks.log"
  local rc2=${PIPESTATUS[0]}
  docker exec "${PREFIX}mon01" alvos > "${EVID}/monitoramento-alvos.txt" 2>&1 || true
  return $(( rc1 || rc2 ))
}

drill() {
  set +e
  mkdir -p "${EVID}"
  EXEC="docker exec" PREFIX="${PREFIX}" bash "${REPO}/tests/alert-drill.sh" 2>&1 | tee "${EVID}/simulacao-alerta.log"
  return "${PIPESTATUS[0]}"
}

backup_drill() {
  set +e
  mkdir -p "${EVID}"
  EXEC="docker exec" PREFIX="${PREFIX}" bash "${REPO}/tests/backup-drill.sh" 2>&1 | tee "${EVID}/teste-restauracao-backup.log"
  return "${PIPESTATUS[0]}"
}

evidence() {
  EXEC="docker exec" PREFIX="${PREFIX}" EVID_DIR="${EVID}" bash "${REPO}/tests/coletar-evidencias.sh"
}

down() {
  for n in "${ORDER[@]}"; do docker rm -f "${PREFIX}${n}" >/dev/null 2>&1 || true; done
  docker network rm "${NET}" >/dev/null 2>&1 || true
}

case "${1:-all}" in
  up)    up ;;
  test)  run_test ;;
  drill)  drill ;;
  backup) backup_drill ;;
  evidence) evidence ;;
  down)   down ;;
  all)    up && run_test && drill && backup_drill && evidence ;;
  *)      echo "uso: $0 up|test|drill|backup|evidence|down|all"; exit 2 ;;
esac

#!/usr/bin/env bash
# =============================================================================
#  backup-drill.sh — teste de restauração: "o backup do AD funciona mesmo?"
#  Faz backup, apaga um usuário "por engano", restaura e confere se ele voltou
#  com os mesmos grupos. Backup que nunca foi restaurado não é backup.
#
#  Na sua máquina (Git Bash), na pasta do repositório:
#    bash tests/backup-drill.sh                # usa "vagrant ssh"
#  Harness de contêineres: EXEC="docker exec" PREFIX="hl-" ...
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/provision/lab.env"
EXEC="${EXEC:-vagrant}"
VICTIM="carla.mendes"

run_on() {
  if [ "${EXEC}" = "vagrant" ]; then
    vagrant ssh "$1" -c "echo $(printf '%s' "$2" | base64 -w0) | base64 -d | sudo bash" 2>/dev/null | tr -d '\r'
  else ${EXEC} "${PREFIX:-}$1" bash -c "$2"; fi
}
ADM="-H ldap://127.0.0.1 -U Administrator%${LAB_ADMIN_PASSWORD}"
ts() { date '+%H:%M:%S'; }
groups_of() { run_on dc01 "samba-tool user getgroups ${VICTIM} ${ADM} 2>/dev/null | sort | tr '\n' ' '"; }

BEFORE="$(groups_of)"
[ -n "${BEFORE}" ] || { echo "FALHOU: ${VICTIM} não existe antes do teste"; exit 1; }
echo "[$(ts)] ${VICTIM} existe; grupos: ${BEFORE}"

echo "[$(ts)] 1. Fazendo backup (backup-dc)"
run_on dc01 "backup-dc"

echo "[$(ts)] 2. DESASTRE simulado: apagando ${VICTIM}"
run_on dc01 "samba-tool user delete ${VICTIM} ${ADM} >/dev/null 2>&1"
[ -z "$(groups_of)" ] && echo "[$(ts)]    confirmado: ${VICTIM} não existe mais"

echo "[$(ts)] 3. Restaurando o backup mais recente (restaurar-dc)"
run_on dc01 "restaurar-dc \$(ls -t /var/backups/dc01/dc01-*.tar.gz | head -1)"
run_on dc01 "for i in \$(seq 1 60); do ldbsearch ${ADM} -b ${LAB_BASE_DN} -s base dn >/dev/null 2>&1 && break; sleep 1; done"

AFTER="$(groups_of)"
echo "[$(ts)] 4. Conferência: grupos de ${VICTIM} depois: ${AFTER}"
run_on dc01 "samba-tool dbcheck --cross-ncs 2>&1 | tail -1"
if [ "${AFTER}" = "${BEFORE}" ]; then
  echo "Teste de restauração concluído com sucesso: usuário e grupos recuperados."
else
  echo "FALHOU: estado depois da restauração diferente do anterior"; exit 1
fi

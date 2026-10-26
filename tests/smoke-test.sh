#!/usr/bin/env bash
# =============================================================================
#  smoke-test.sh — "o laboratório está funcionando?"
#  Roda na ws01 (estação do domínio), do ponto de vista de um funcionário.
#    VM:        vagrant ssh ws01 -c "sudo /opt/homelab/tests/smoke-test.sh"
#    contêiner: tests/container-lab/run-lab.sh test
#  Sai com código 0 se tudo passou, 1 se algo falhou.
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../provision/lab.env
source "${ROOT}/provision/lab.env"

PASS=0; FAIL=0
# cores só no terminal; em arquivo de log sai texto limpo
if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; B=$'\033[1m'; N=$'\033[0m'; else G=; R=; B=; N=; fi
FQDN_FS="fs01.${LAB_DOMAIN}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

check() { # descrição, comando...
  local desc="$1"; shift
  if "$@" >"$TMP/out" 2>&1; then
    printf '  %s[PASSOU]%s %s\n' "$G" "$N" "$desc"; PASS=$((PASS + 1))
  else
    printf '  %s[FALHOU]%s %s\n' "$R" "$N" "$desc"; FAIL=$((FAIL + 1))
    sed 's/^/           | /' "$TMP/out" | head -5
  fi
}
must_fail() { ! "$@"; }               # passa quando o comando É negado
section() { printf '\n%s== %s ==%s\n' "$B" "$1" "$N"; }

# Kerberos: pega um ticket para o usuário num cache próprio
login_as() { # usuario
  export KRB5CCNAME="FILE:${TMP}/krb5cc_$1"
  printf '%s\n' "${LAB_USER_PASSWORD}" | kinit "$1@${LAB_REALM}" >/dev/null 2>&1
}
smb_as() { # usuario compartilhamento comando-smbclient
  login_as "$1" || return 1
  smbclient "//${FQDN_FS}/$2" --use-kerberos=required -c "$3" >"${TMP}/smb.log" 2>&1
  local rc=$?
  cat "${TMP}/smb.log"
  # smbclient às vezes sai com 0 mesmo com NT_STATUS_ACCESS_DENIED no comando
  if grep -q 'NT_STATUS_' "${TMP}/smb.log"; then return 1; fi
  return $rc
}

echo "Teste de fumaça do homelab ${LAB_REALM} — $(date '+%d/%m/%Y %H:%M:%S') — host $(hostname -s)"

# -----------------------------------------------------------------------------
section "1. DNS"
check "dc01.${LAB_DOMAIN} resolve para ${DC01_IP}"   bash -c "dig +short dc01.${LAB_DOMAIN} | grep -qx ${DC01_IP}"
check "fs01.${LAB_DOMAIN} resolve para ${FS01_IP}"   bash -c "dig +short fs01.${LAB_DOMAIN} | grep -qx ${FS01_IP}"
check "mon01.${LAB_DOMAIN} resolve para ${MON01_IP}" bash -c "dig +short mon01.${LAB_DOMAIN} | grep -qx ${MON01_IP}"
check "apelido arquivos.${LAB_DOMAIN} aponta para o fs01" bash -c "dig +short arquivos.${LAB_DOMAIN} | grep -q fs01"
check "reverso de ${FS01_IP} é fs01"                 bash -c "dig +short -x ${FS01_IP} | grep -q fs01.${LAB_DOMAIN}"
check "registro SRV do LDAP (_ldap._tcp)"            bash -c "dig +short _ldap._tcp.${LAB_DOMAIN} SRV | grep -q dc01"
check "registro SRV do Kerberos (_kerberos._tcp)"    bash -c "dig +short _kerberos._tcp.${LAB_DOMAIN} SRV | grep -q dc01"

# -----------------------------------------------------------------------------
section "2. DHCP"
LAN="${LAN_IF:-}"
if [ -z "${LAN}" ]; then
  LAN="$(ip -o -4 addr show | awk -v p="${LAB_NET_PREFIX}." '$4 ~ "^"p {print $2; exit}')"
fi
if [ "${LAB_PLATFORM}" != "container" ]; then
  check "ws01 recebeu IP do escopo ${DHCP_POOL_START}-${DHCP_POOL_END}" bash -c \
    "ip -4 addr show ${LAN} | grep -oE 'inet ${LAB_NET_PREFIX}\.[0-9]+' | awk -F. '\$4>=${DHCP_POOL_START##*.} && \$4<=${DHCP_POOL_END##*.}' | grep -q ."
fi
cat > "${TMP}/dhcp-script.sh" <<'EOF'
#!/bin/sh
[ "$1" = bound ] && echo "ip=$ip dns=$dns domain=$domain lease=$lease" >> "$DHCP_OUT"
exit 0
EOF
chmod +x "${TMP}/dhcp-script.sh"
export DHCP_OUT="${TMP}/dhcp.out"
busybox udhcpc -i "${LAN}" -n -q -t 4 -T 2 -s "${TMP}/dhcp-script.sh" -O dns -O domain >/dev/null 2>&1
check "servidor DHCP responde a uma solicitação (DISCOVER/OFFER)" test -s "${DHCP_OUT}"
check "DHCP entrega DNS = ${DC01_IP}"                bash -c "grep -q 'dns=${DC01_IP}' ${DHCP_OUT}"
check "DHCP entrega o domínio ${LAB_DOMAIN}"         bash -c "grep -q 'domain=${LAB_DOMAIN}' ${DHCP_OUT}"
check "IP entregue está dentro do escopo"            bash -c \
  "grep -oE 'ip=${LAB_NET_PREFIX}\.[0-9]+' ${DHCP_OUT} | awk -F. '\$4>=${DHCP_POOL_START##*.} && \$4<=${DHCP_POOL_END##*.}' | grep -q ."
[ -s "${DHCP_OUT}" ] && sed 's/^/           oferta: /' "${DHCP_OUT}"

# -----------------------------------------------------------------------------
section "3. Active Directory e Kerberos"
check "ws01 é membro do domínio ${LAB_DOMAIN}"       adcli testjoin --domain="${LAB_DOMAIN}"
check "usuário ana.souza existe para o sistema"      id ana.souza
check "bruno.lima pertence ao GG_Financeiro"         bash -c "id -Gn bruno.lima | tr ' ' '\n' | grep -qix gg_financeiro"
check "elisa.costa pertence ao GG_Diretoria"         bash -c "id -Gn elisa.costa | tr ' ' '\n' | grep -qix gg_diretoria"
check "bruno.lima obtém ticket Kerberos com a senha" login_as bruno.lima
check "senha errada é recusada"                      bash -c "printf 'errada\n' | KRB5CCNAME=FILE:${TMP}/x kinit carla.mendes@${LAB_REALM} 2>&1 | grep -qiE 'incorrect|preauth'"

# -----------------------------------------------------------------------------
section "4. Compartilhamentos e permissões"
echo "teste $(date +%s)" > "${TMP}/teste.txt"
cd "${TMP}" || exit 1
check "Financeiro: bruno.lima (GG_Financeiro) grava"          smb_as bruno.lima   Financeiro "put teste.txt teste-bruno.txt; del teste-bruno.txt"
check "Financeiro: elisa.costa (GG_Diretoria) lê"             smb_as elisa.costa  Financeiro "get LEIA-ME.txt lido.txt"
check "Financeiro: elisa.costa (GG_Diretoria) NÃO grava"      must_fail smb_as elisa.costa Financeiro "put teste.txt teste-elisa.txt"
check "Financeiro: diego.rocha (RH) NÃO acessa"               must_fail smb_as diego.rocha Financeiro "ls"
check "RH: diego.rocha (GG_RH) grava"                         smb_as diego.rocha  RH "put teste.txt teste-diego.txt; del teste-diego.txt"
check "RH: felipe.alves (Comercial) NÃO acessa"               must_fail smb_as felipe.alves RH "ls"
check "Publico: felipe.alves (Domain Users) grava"            smb_as felipe.alves Publico "put teste.txt teste-felipe.txt; del teste-felipe.txt"
check "TI: ana.souza (GG_TI) grava"                           smb_as ana.souza TI "put teste.txt teste-ana.txt; del teste-ana.txt"
login_as diego.rocha
smbclient -L "//${FQDN_FS}" --use-kerberos=required 2>/dev/null > "${TMP}/lista.txt"
check "diego.rocha só ENXERGA os compartilhamentos que pode abrir" bash -c \
  "grep -qE '^[[:space:]]+RH[[:space:]]' ${TMP}/lista.txt && ! grep -q 'Financeiro' ${TMP}/lista.txt"

# -----------------------------------------------------------------------------
section "5. Monitoramento"
PROM="http://mon01.${LAB_DOMAIN}:9090"
curl -sf "${PROM}/api/v1/targets" > "${TMP}/targets.json"
check "Prometheus responde"                          test -s "${TMP}/targets.json"
check "todos os alvos monitorados estão UP"          bash -c \
  "jq -e '[.data.activeTargets[] | select(.health != \"up\")] | length == 0' ${TMP}/targets.json"
jq -r '.data.activeTargets[] | "           \(.health | ascii_upcase)  \(.labels.job)  \(.labels.instance)"' "${TMP}/targets.json" 2>/dev/null
check "nenhum alerta disparado agora"                bash -c \
  "curl -sf ${PROM}/api/v1/alerts | jq -e '[.data.alerts[] | select(.state == \"firing\")] | length == 0'"
check "Alertmanager responde"                        curl -sf "http://mon01.${LAB_DOMAIN}:9093/-/ready"

# -----------------------------------------------------------------------------
printf '\n%sResultado: %d passaram, %d falharam%s\n' "$B" "$PASS" "$FAIL" "$N"
[ "$FAIL" -eq 0 ]

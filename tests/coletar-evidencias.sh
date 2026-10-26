#!/usr/bin/env bash
# =============================================================================
#  coletar-evidencias.sh — tira uma "fotografia" do estado REAL do ambiente
#  e grava em docs/evidencias/. Use para conferir se o inventário
#  (docs/01-inventario.md) ainda bate com a realidade.
#
#  Na sua máquina (Git Bash), na pasta do repositório:
#    bash tests/coletar-evidencias.sh            # usa "vagrant ssh"
#  Harness de contêineres: EXEC="docker exec" PREFIX="hl-" ...
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/provision/lab.env"
EXEC="${EXEC:-vagrant}"
OUT="${EVID_DIR:-${ROOT}/docs/evidencias}"
mkdir -p "${OUT}"

# Roda um comando como root numa máquina. Via vagrant, o comando vai em base64
# para não brigar com aspas.
run_on() {
  if [ "${EXEC}" = "vagrant" ]; then
    vagrant ssh "$1" -c "echo $(printf '%s' "$2" | base64 -w0) | base64 -d | sudo bash" 2>/dev/null | tr -d '\r'
  else ${EXEC} "${PREFIX:-}$1" bash -c "$2"; fi
}
AUTH="-U Administrator%${LAB_ADMIN_PASSWORD}"
ADM="${AUTH} -H ldap://127.0.0.1"
# LDIF guarda texto com acento em base64 ("atributo:: ...") — decodifica
decode_ldif() {
  local line
  while IFS= read -r line; do
    if [[ "$line" == *":: "* ]]; then
      printf '%s: %s\n' "${line%%::*}" "$(printf '%s' "${line#*:: }" | base64 -d)"
    else printf '%s\n' "$line"; fi
  done
}
header() { printf '# %s\n# coletado em %s\n\n' "$1" "$(date '+%d/%m/%Y %H:%M:%S')"; }

{
  header "Active Directory — estrutura, usuários e grupos (dc01)"
  echo "## Domínio"; run_on dc01 "samba-tool domain info 127.0.0.1 2>/dev/null"
  echo; echo "## Unidades organizacionais"; run_on dc01 "samba-tool ou list ${ADM} 2>/dev/null | sort"
  echo; echo "## Usuários (login | departamento | cargo | OU)"
  run_on dc01 "ldbsearch ${ADM} -o ldif-wrap=no -b OU=Usuarios,OU=CORP,${LAB_BASE_DN} '(objectClass=user)' sAMAccountName department title 2>/dev/null" \
    | decode_ldif \
    | awk '/^dn:/{sub(/^dn: /,""); dn=$0} /^sAMAccountName:/{u=$2} /^department:/{d=$2} /^title:/{sub(/^title: /,""); t=$0}
           /^$/ && u {printf "%-14s | %-11s | %-26s | %s\n", u, d, t, dn; u=""}' | sort
  echo; echo "## Membros dos grupos"
  for g in GG_TI GG_Financeiro GG_RH GG_Comercial GG_Diretoria GG_Helpdesk; do
    printf '%-14s: %s\n' "$g" "$(run_on dc01 "samba-tool group listmembers $g ${ADM} 2>/dev/null | sort | tr '\n' ' '")"
  done
  echo; echo "## Computadores do domínio"; run_on dc01 "samba-tool computer list ${ADM} 2>/dev/null | sort"
  echo; echo "## Política de senha"; run_on dc01 "samba-tool domain passwordsettings show ${ADM} 2>/dev/null"
} > "${OUT}/ad-usuarios-grupos.txt"

{
  header "DNS — zona ${LAB_DOMAIN} e reversa (dc01)"
  echo "## Zonas"; run_on dc01 "samba-tool dns zonelist 127.0.0.1 ${AUTH} 2>/dev/null | grep -E 'pszZoneName'"
  echo; echo "## Registros da zona ${LAB_DOMAIN} (raiz e hosts)"
  run_on dc01 "samba-tool dns query 127.0.0.1 ${LAB_DOMAIN} @ ALL ${AUTH} 2>/dev/null | grep -E 'Name=|A:|CNAME:|NS:' | sed -E 's/^ *//; s/ \\(flags.*//'"
  echo; echo "## Registros da zona reversa ${LAB_REVERSE_ZONE}"
  run_on dc01 "samba-tool dns query 127.0.0.1 ${LAB_REVERSE_ZONE} @ ALL ${AUTH} 2>/dev/null | grep -E 'Name=|PTR:' | sed -E 's/^ *//; s/ \\(flags.*//'"
} > "${OUT}/dns-registros.txt"

{
  header "DHCP — configuração ativa e concessões (dc01, Kea)"
  echo "## Escopo e opções"; run_on dc01 "grep -vE '^\s*//' /etc/kea/kea-dhcp4.conf | grep -E 'subnet\"|pool|domain|ntp|valid-lifetime|hw-address|ip-address'"
  echo; echo "## Concessões (leases) registradas"; run_on dc01 "cat /var/lib/kea/kea-leases4.csv 2>/dev/null | cut -d, -f1,2,4,9 | awk '!visto[\$0]++' | column -t -s,"
} > "${OUT}/dhcp-concessoes.txt"

{
  header "Servidor de arquivos — compartilhamentos e permissões (fs01)"
  echo "## Compartilhamentos (testparm)"; run_on fs01 "testparm -s 2>/dev/null | sed -n '/^\[Publico\]/,\$p'"
  echo; echo "## ACLs das pastas"; run_on fs01 "for d in /srv/compartilhamentos/*; do getfacl -p --omit-header \$d | grep -v default; echo; done"
  echo "## Conferência do ingresso no domínio"; run_on fs01 "net ads testjoin 2>&1; wbinfo -t 2>&1"
} > "${OUT}/arquivos-permissoes.txt"

{
  header "Monitoramento — alvos e alertas (mon01)"
  echo "## Alvos"; run_on mon01 "alvos"
  echo; echo "## Alertas ativos (vazio = nenhum)"; run_on mon01 "alertas"
  echo; echo "## Regras de alerta carregadas"
  run_on mon01 "curl -s localhost:9090/api/v1/rules | jq -r '.data.groups[].rules[] | \"\(.name)  [\(.health)]\"'"
} > "${OUT}/monitoramento-alvos.txt"

echo "Evidências gravadas em ${OUT}:"; ls -1 "${OUT}"

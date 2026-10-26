#!/usr/bin/env bash
# =============================================================================
#  dc-checks.sh — verificações feitas no próprio dc01
#    VM:        vagrant ssh dc01 -c "sudo /opt/homelab/tests/dc-checks.sh"
#  Confere a saúde do banco do AD, a política de senha e a delegação do
#  GG_Helpdesk (pode redefinir senha de usuário comum, não de administrador).
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/provision/lab.env"
PASS=0; FAIL=0
# cores só no terminal; em arquivo de log sai texto limpo
if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; B=$'\033[1m'; N=$'\033[0m'; else G=; R=; B=; N=; fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ADM=(-U "Administrator%${LAB_ADMIN_PASSWORD}" -H ldap://127.0.0.1)

check() {
  local desc="$1"; shift
  if "$@" >"$TMP/out" 2>&1; then printf '  %s[PASSOU]%s %s\n' "$G" "$N" "$desc"; PASS=$((PASS+1))
  else printf '  %s[FALHOU]%s %s\n' "$R" "$N" "$desc"; FAIL=$((FAIL+1)); sed 's/^/           | /' "$TMP/out" | head -5; fi
}
must_fail() { ! "$@"; }

echo "Verificações do dc01 — $(date '+%d/%m/%Y %H:%M:%S')"
printf '\n%s== Saúde do AD ==%s\n' "$B" "$N"
check "serviço samba-ad-dc ativo"               systemctl is-active samba-ad-dc
check "serviço kea-dhcp4-server ativo"          systemctl is-active kea-dhcp4-server
check "banco do AD íntegro (samba-tool dbcheck)" bash -c "samba-tool dbcheck --cross-ncs 2>&1 | grep -q 'Checked .* objects (0 errors)'"
check "nível funcional do domínio 2008 R2+"     bash -c "samba-tool domain level show ${ADM[*]} | grep -Eq 'Domain function level: \(Windows\) 20(08 R2|12|12 R2|16)'"
check "política: mínimo de 10 caracteres"       bash -c "samba-tool domain passwordsettings show ${ADM[*]} | grep -q 'Minimum password length: 10'"
check "política: bloqueio após 5 tentativas"    bash -c "samba-tool domain passwordsettings show ${ADM[*]} | grep -q 'Account lockout threshold (attempts): 5'"
check "7 usuários do CSV estão no AD"           bash -c "[ \$(samba-tool user list ${ADM[*]} | grep -c '\\.') -eq 7 ]"

printf '\n%s== Delegação do Helpdesk ==%s\n' "$B" "$N"
NOVA="Lab@Reset$(date +%H%M)x"
check "rafael.nunes (GG_Helpdesk) redefine a senha de felipe.alves" \
  samba-tool user setpassword felipe.alves --newpassword="${NOVA}" -H ldap://dc01."${LAB_DOMAIN}" -U "rafael.nunes%${LAB_USER_PASSWORD}"
check "diego.rocha (sem delegação) NÃO consegue redefinir senha" \
  must_fail samba-tool user setpassword felipe.alves --newpassword="${NOVA}2" -H ldap://dc01."${LAB_DOMAIN}" -U "diego.rocha%${LAB_USER_PASSWORD}"
check "rafael.nunes NÃO redefine a senha do Administrator" \
  must_fail samba-tool user setpassword Administrator --newpassword="${NOVA}3" -H ldap://dc01."${LAB_DOMAIN}" -U "rafael.nunes%${LAB_USER_PASSWORD}"
# devolve a senha padrão do laboratório
samba-tool user setpassword felipe.alves --newpassword="${LAB_USER_PASSWORD}" "${ADM[@]}" >/dev/null 2>&1

printf '\n%sResultado: %d passaram, %d falharam%s\n' "$B" "$PASS" "$FAIL" "$N"
[ "$FAIL" -eq 0 ]

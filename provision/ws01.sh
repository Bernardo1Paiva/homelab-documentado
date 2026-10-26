#!/usr/bin/env bash
# =============================================================================
#  ws01.sh — Estação de trabalho de um funcionário (cliente Linux do domínio)
#  Recebe IP por DHCP do dc01, entra no domínio com realmd/SSSD e serve como
#  "ponto de vista do usuário" para os testes (tests/smoke-test.sh).
#  Para ingressar uma estação Windows: docs/runbooks/RB-07-estacao-windows.md
# =============================================================================
source "$(dirname "$0")/lib/common.sh"

base_setup ws01 dhcp "sssd"

echo "krb5-config krb5-config/default_realm string ${LAB_REALM}" | debconf-set-selections
apt_install realmd sssd sssd-ad sssd-tools adcli libnss-sss libpam-sss \
            krb5-user smbclient cifs-utils busybox jq packagekit

# Na VM o IP e o DNS vêm do DHCP. Confere se chegaram antes de seguir.
if is_container; then
  write_resolv_conf "${DC01_IP}"
else
  wait_for 60 "IP do DHCP na ${LAN_IF}" sh -c "ip -4 addr show ${LAN_IF} | grep -q 'inet ${LAB_NET_PREFIX}\.'"
fi
wait_for 120 "domínio ${LAB_DOMAIN} descoberto" realm discover "${LAB_DOMAIN}"

cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = ${LAB_REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = true
    rdns = false
EOF

if ! realm list --name-only 2>/dev/null | grep -qx "${LAB_DOMAIN}"; then
  log "ingressando ws01 no domínio ${LAB_DOMAIN}"
  printf '%s' "${LAB_ADMIN_PASSWORD}" | realm join --unattended \
    --membership-software=adcli --client-software=sssd \
    --computer-ou="OU=Estacoes,OU=CORP,${LAB_BASE_DN}" \
    -U Administrator "${LAB_DOMAIN}"
else
  log "ws01 já é membro do domínio"
fi

# Login com "ana.souza" (sem @corp.lab) e pasta pessoal criada no 1º acesso
sed -i -E 's/^use_fully_qualified_names = .*/use_fully_qualified_names = False/' /etc/sssd/sssd.conf
sed -i -E 's|^fallback_homedir = .*|fallback_homedir = /home/%u|' /etc/sssd/sssd.conf
grep -q '^ad_gpo_access_control' /etc/sssd/sssd.conf || \
  sed -i "/^\[domain\/${LAB_DOMAIN}\]/a ad_gpo_access_control = permissive" /etc/sssd/sssd.conf
pam-auth-update --enable mkhomedir >/dev/null 2>&1 || true
sss_cache -E >/dev/null 2>&1 || true
systemctl restart sssd
wait_for 60 "usuários do domínio visíveis na ws01" id ana.souza

# Os testes ficam disponíveis na própria estação
mkdir -p "${LAB_ROOT}"
ok "ws01 pronta: membro de ${LAB_DOMAIN}, rode: sudo ${LAB_ROOT}/tests/smoke-test.sh"

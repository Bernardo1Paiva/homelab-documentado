#!/usr/bin/env bash
# =============================================================================
#  ws01.sh — Estação de trabalho de um funcionário (cliente Linux do domínio)
#  Recebe IP por DHCP do dc01, entra no domínio com adcli + SSSD e serve como
#  "ponto de vista do usuário" para os testes (tests/smoke-test.sh).
#  Para ingressar uma estação Windows: docs/runbooks/RB-07-estacao-windows.md
#
#  Por que adcli + sssd.conf, e não "realm join"? O realm faz exatamente isso
#  por baixo, mas depende de PackageKit e polkit (pensados para desktop) e
#  travou em ambiente sem interface. Ver CHANGELOG.
# =============================================================================
source "$(dirname "$0")/lib/common.sh"

base_setup ws01 dhcp "sssd"

echo "krb5-config krb5-config/default_realm string ${LAB_REALM}" | debconf-set-selections
apt_install sssd-ad sssd-tools adcli libnss-sss libpam-sss \
            krb5-user smbclient cifs-utils busybox jq

# Na VM o IP e o DNS vêm do DHCP. Confere se chegaram antes de seguir.
if is_container; then
  write_resolv_conf "${DC01_IP}"
else
  wait_for 60 "IP do DHCP na ${LAN_IF}" sh -c "ip -4 addr show ${LAN_IF} | grep -q 'inet ${LAB_NET_PREFIX}\.'"
fi
# "adcli info" acha o controlador de domínio pelos registros SRV do DNS
wait_for 120 "controlador do domínio ${LAB_DOMAIN} encontrado" adcli info "${LAB_DOMAIN}"

cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = ${LAB_REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = true
    rdns = false
EOF

# --- Ingresso no domínio (cria a conta WS01$ e o /etc/krb5.keytab) ----------
if ! adcli testjoin --domain="${LAB_DOMAIN}" >/dev/null 2>&1; then
  log "ingressando ws01 no domínio ${LAB_DOMAIN}"
  printf '%s' "${LAB_ADMIN_PASSWORD}" | timeout 120 adcli join \
    --domain="${LAB_DOMAIN}" \
    --domain-ou="OU=Estacoes,OU=CORP,${LAB_BASE_DN}" \
    --login-user=Administrator --stdin-password \
    --host-fqdn="ws01.${LAB_DOMAIN}"
else
  log "ws01 já é membro do domínio"
fi

# --- SSSD: quem é usuário e quem pode entrar ------------------------------------
cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = ${LAB_DOMAIN}
config_file_version = 2
services = nss, pam

[domain/${LAB_DOMAIN}]
id_provider = ad
access_provider = ad
ad_domain = ${LAB_DOMAIN}
krb5_realm = ${LAB_REALM}
ldap_id_mapping = True
# login com "ana.souza" (sem @corp.lab); pasta pessoal criada no 1º acesso
use_fully_qualified_names = False
fallback_homedir = /home/%u
default_shell = /bin/bash
# permite login mesmo com o DC fora do ar, com a última senha usada
cache_credentials = True
krb5_store_password_if_offline = True
# laboratório: GPOs não bloqueiam o login no Linux
ad_gpo_access_control = permissive
# registra o IP da estação no DNS do domínio
dyndns_update = True
EOF
chmod 600 /etc/sssd/sssd.conf

grep -qE '^passwd:.*sss' /etc/nsswitch.conf || sed -i -E 's/^(passwd|group|shadow):(.*)$/\1:\2 sss/' /etc/nsswitch.conf
pam-auth-update --enable mkhomedir >/dev/null 2>&1 || true
sss_cache -E >/dev/null 2>&1 || true
systemctl enable sssd >/dev/null 2>&1
systemctl restart sssd
wait_for 60 "usuários do domínio visíveis na ws01" id ana.souza

ok "ws01 pronta: membro de ${LAB_DOMAIN}, rode: sudo ${LAB_ROOT}/tests/smoke-test.sh"

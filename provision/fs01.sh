#!/usr/bin/env bash
# =============================================================================
#  fs01.sh — Servidor de arquivos (membro do domínio CORP.LAB)
#  Papéis: compartilhamentos SMB com permissão por grupo do AD
#  Passo a passo manual equivalente: docs/runbooks/RB-05-servidor-de-arquivos.md
# =============================================================================
source "$(dirname "$0")/lib/common.sh"

SHARES_ROOT="/srv/compartilhamentos"

base_setup fs01 "${FS01_IP}" "smbd winbind"

echo "krb5-config krb5-config/default_realm string ${LAB_REALM}" | debconf-set-selections
apt_install samba samba-vfs-modules winbind libnss-winbind libpam-winbind \
            krb5-user smbclient acl attr

# --- 1. DNS e Kerberos apontando para o dc01 -----------------------------------
if is_container; then write_resolv_conf "${DC01_IP}"; fi
wait_for 120 "dc01 resolvendo o domínio" dig +short "_ldap._tcp.${LAB_DOMAIN}" SRV @"${DC01_IP}"

cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = ${LAB_REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = true
EOF

# --- 2. Samba como membro do domínio -----------------------------------------
render "${PROVISION_DIR}/files/smb-fs01.conf.tpl" /etc/samba/smb.conf
touch /etc/samba/shares.conf
testparm -s /etc/samba/smb.conf >/dev/null 2>&1 || die "smb.conf inválido"

sed -i -E 's/^(passwd|group):.*/\1:         files systemd winbind/' /etc/nsswitch.conf

if ! net ads testjoin >/dev/null 2>&1; then
  log "ingressando fs01 no domínio ${LAB_REALM}"
  net ads join -U "Administrator%${LAB_ADMIN_PASSWORD}" \
      createcomputer="CORP/Servidores" --no-dns-updates
else
  log "fs01 já é membro do domínio"
fi

systemctl disable --now nmbd >/dev/null 2>&1 || true
systemctl enable winbind smbd >/dev/null 2>&1
systemctl restart winbind
wait_for 60 "canal seguro com o DC (wbinfo -t)" wbinfo -t
systemctl restart smbd
wait_for 60 "usuários do AD visíveis no fs01" getent passwd ana.souza

# Domain Admins podem gerenciar permissões dos compartilhamentos pelo Windows
net rpc rights grant "${LAB_NETBIOS}\\Domain Admins" SeDiskOperatorPrivilege \
    -U "Administrator%${LAB_ADMIN_PASSWORD}" -S localhost >/dev/null 2>&1 || true

# --- 3. Compartilhamentos a partir do CSV --------------------------------------
mkdir -p "${SHARES_ROOT}"
chmod 755 "${SHARES_ROOT}"
: > /etc/samba/shares.conf

tail -n +2 "${PROVISION_DIR}/data/compartilhamentos.csv" | while IFS=';' read -r nome rw ro descricao; do
  [ -z "${nome}" ] && continue
  dir="${SHARES_ROOT}/${nome}"
  mkdir -p "${dir}"

  # A permissão de verdade fica na PASTA (ACL, herdada por arquivos novos),
  # como no NTFS: as permissões dos grupos se SOMAM. Não usamos "read list"
  # no compartilhamento porque ela VENCE a ACL — quem está num grupo de
  # escrita e também num de leitura ficaria só com leitura (ver TS-04).
  chown root:"domain admins" "${dir}"
  chmod 2770 "${dir}"
  setfacl -b "${dir}"
  setfacl -m  "g:domain admins:rwx,g:${rw}:rwx" "${dir}"
  setfacl -dm "g:domain admins:rwx,g:${rw}:rwx,u::rwx,g::rwx,o::---" "${dir}"
  valid="@\"${rw}\" @\"domain admins\""
  if [ -n "${ro}" ]; then
    setfacl -m  "g:${ro}:rx" "${dir}"
    setfacl -dm "g:${ro}:rx" "${dir}"
    valid="${valid} @\"${ro}\""
  fi

  cat >> /etc/samba/shares.conf <<EOF

[${nome}]
   comment = ${descricao}
   path = ${dir}
   read only = no
   valid users = ${valid}
   inherit acls = yes
   create mask = 0660
   directory mask = 2770
EOF
  log "compartilhamento \\\\fs01\\${nome}: escrita=${rw}${ro:+, leitura=${ro}}"
done

# Arquivo de boas-vindas em cada pasta, útil para os testes de leitura
for d in "${SHARES_ROOT}"/*/; do
  [ -f "${d}LEIA-ME.txt" ] || echo "Pasta $(basename "$d") — gerenciada pela TI. Dúvidas: chamado no helpdesk." > "${d}LEIA-ME.txt"
done

testparm -s >/dev/null 2>&1 || die "smb.conf inválido depois dos compartilhamentos"
smbcontrol smbd reload-config
ok "fs01 pronto: $(grep -c '^\[' /etc/samba/shares.conf) compartilhamentos em ${SHARES_ROOT}"

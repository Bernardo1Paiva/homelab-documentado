#!/usr/bin/env bash
# =============================================================================
#  dc01.sh — Controlador de domínio CORP.LAB
#  Papéis: Active Directory (Samba AD DC), DNS do domínio, DHCP (Kea), NTP
#  Idempotente: pode rodar de novo com "vagrant provision dc01".
#  Passo a passo manual equivalente: docs/runbooks/RB-01-controlador-de-dominio.md
# =============================================================================
source "$(dirname "$0")/lib/common.sh"

base_setup dc01 "${DC01_IP}" "samba-ad-dc kea-dhcp4-server"

# --- 1. Pacotes ------------------------------------------------------------------
# krb5-config pergunta o realm na instalação: respondemos antes.
echo "krb5-config krb5-config/default_realm string ${LAB_REALM}" | debconf-set-selections
apt_install samba samba-ad-dc samba-ad-provision winbind libnss-winbind \
            krb5-user smbclient ldb-tools python3-samba python3-setproctitle \
            kea-dhcp4-server acl attr

# --- 2. Promover a controlador de domínio ---------------------------------------
if [ ! -f /var/lib/samba/private/sam.ldb ]; then
  log "promovendo dc01 a controlador de domínio ${LAB_REALM}"
  # serviços de servidor-membro não rodam num DC
  systemctl disable --now smbd nmbd winbind >/dev/null 2>&1 || true
  systemctl mask smbd nmbd winbind >/dev/null 2>&1 || true
  rm -f /etc/samba/smb.conf
  rm -rf /var/lib/samba/private/* /var/lib/samba/sysvol/* 2>/dev/null || true

  samba-tool domain provision \
    --realm="${LAB_REALM}" \
    --domain="${LAB_NETBIOS}" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --host-ip="${DC01_IP}" \
    --adminpass="${LAB_ADMIN_PASSWORD}" \
    --option="dns forwarder = ${DNS_FORWARDER}" \
    --option="interfaces = lo ${LAN_IF}" \
    --option="bind interfaces only = yes" \
    --option="disable netbios = yes" \
    --option="log level = 1 auth_audit:3" \
    > /var/log/samba-provision.log

  cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
else
  log "domínio já provisionado, pulando promoção"
fi

# O próprio DC resolve nomes nele mesmo (o resolved do Ubuntu sairia da frente)
if ! is_container; then
  systemctl disable --now systemd-resolved >/dev/null 2>&1 || true
fi
write_resolv_conf 127.0.0.1

systemctl unmask samba-ad-dc >/dev/null 2>&1 || true
systemctl enable samba-ad-dc >/dev/null 2>&1
systemctl restart samba-ad-dc
wait_for 90 "Samba AD respondendo LDAP" ldbsearch -H ldap://127.0.0.1 -U "Administrator%${LAB_ADMIN_PASSWORD}" -b "${LAB_BASE_DN}" -s base dn
wait_for 60 "DNS do domínio respondendo" dig +short @127.0.0.1 "dc01.${LAB_DOMAIN}"

ADM=(-U "Administrator%${LAB_ADMIN_PASSWORD}")

# --- 3. DNS: zona reversa, registros e apelidos --------------------------------
dns_add() { # zona nome tipo dado
  if ! samba-tool dns query 127.0.0.1 "$1" "$2" "$3" "${ADM[@]}" >/dev/null 2>&1; then
    samba-tool dns add 127.0.0.1 "$1" "$2" "$3" "$4" "${ADM[@]}" >/dev/null
    log "DNS: $2.$1 $3 $4"
  fi
}
if ! samba-tool dns zoneinfo 127.0.0.1 "${LAB_REVERSE_ZONE}" "${ADM[@]}" >/dev/null 2>&1; then
  samba-tool dns zonecreate 127.0.0.1 "${LAB_REVERSE_ZONE}" "${ADM[@]}" >/dev/null
  log "zona reversa ${LAB_REVERSE_ZONE} criada"
fi
dns_add "${LAB_DOMAIN}" fs01  A     "${FS01_IP}"
dns_add "${LAB_DOMAIN}" mon01 A     "${MON01_IP}"
dns_add "${LAB_DOMAIN}" impressora01 A "${PRINTER_IP}"
dns_add "${LAB_DOMAIN}" arquivos CNAME "fs01.${LAB_DOMAIN}"
dns_add "${LAB_DOMAIN}" monitor  CNAME "mon01.${LAB_DOMAIN}"
dns_add "${LAB_REVERSE_ZONE}" "${DC01_IP##*.}"    PTR "dc01.${LAB_DOMAIN}"
dns_add "${LAB_REVERSE_ZONE}" "${FS01_IP##*.}"    PTR "fs01.${LAB_DOMAIN}"
dns_add "${LAB_REVERSE_ZONE}" "${MON01_IP##*.}"   PTR "mon01.${LAB_DOMAIN}"
dns_add "${LAB_REVERSE_ZONE}" "${PRINTER_IP##*.}" PTR "impressora01.${LAB_DOMAIN}"

# --- 4. Estrutura de OUs ---------------------------------------------------------
ou_add() {
  if ! samba-tool ou list "${ADM[@]}" -H ldap://127.0.0.1 2>/dev/null | grep -qx "$1"; then
    samba-tool ou create "$1,${LAB_BASE_DN}" --description="$2" -H ldap://127.0.0.1 "${ADM[@]}" >/dev/null
    log "OU criada: $1"
  fi
}
ou_add "OU=CORP"                         "Raiz dos objetos da empresa"
ou_add "OU=Usuarios,OU=CORP"             "Contas de pessoas"
ou_add "OU=Grupos,OU=CORP"               "Grupos de segurança"
ou_add "OU=Servidores,OU=CORP"           "Contas de computador dos servidores"
ou_add "OU=Estacoes,OU=CORP"             "Contas de computador das estações"
for dep in $(tail -n +2 "${PROVISION_DIR}/data/usuarios.csv" | cut -d';' -f4 | sort -u); do
  ou_add "OU=${dep},OU=Usuarios,OU=CORP" "Usuários do departamento ${dep}"
done

# --- 5. Política de senha e bloqueio ---------------------------------------------
samba-tool domain passwordsettings set \
  --complexity=on --min-pwd-length=10 --history-length=5 \
  --min-pwd-age=0 --max-pwd-age=90 \
  --account-lockout-threshold=5 --account-lockout-duration=15 \
  --reset-account-lockout-after=15 "${ADM[@]}" -H ldap://127.0.0.1 >/dev/null
log "política de senha: 10+ caracteres, complexa, expira em 90 dias, bloqueia após 5 erros por 15 min"

# --- 6. Grupos -------------------------------------------------------------------
group_exists() { samba-tool group show "$1" -H ldap://127.0.0.1 "${ADM[@]}" >/dev/null 2>&1; }
user_exists()  { samba-tool user show  "$1" -H ldap://127.0.0.1 "${ADM[@]}" >/dev/null 2>&1; }

tail -n +2 "${PROVISION_DIR}/data/grupos.csv" | while IFS=';' read -r grupo descricao _extra; do
  [ -z "${grupo}" ] && continue
  if ! group_exists "${grupo}"; then
    samba-tool group add "${grupo}" --groupou="OU=Grupos,OU=CORP" \
      --description="${descricao}" -H ldap://127.0.0.1 "${ADM[@]}" >/dev/null
    log "grupo criado: ${grupo}"
  fi
done

# --- 7. Usuários (a partir do CSV) -----------------------------------------------
tail -n +2 "${PROVISION_DIR}/data/usuarios.csv" | while IFS=';' read -r login nome sobrenome dep cargo; do
  [ -z "${login}" ] && continue
  if ! user_exists "${login}"; then
    samba-tool user create "${login}" "${LAB_USER_PASSWORD}" \
      --given-name="${nome}" --surname="${sobrenome}" \
      --department="${dep}" --job-title="${cargo}" \
      --mail-address="${login}@${LAB_DOMAIN}" \
      --userou="OU=${dep},OU=Usuarios,OU=CORP" \
      -H ldap://127.0.0.1 "${ADM[@]}" >/dev/null
    log "usuário criado: ${login} (${dep})"
  fi
  samba-tool group addmembers "GG_${dep}" "${login}" -H ldap://127.0.0.1 "${ADM[@]}" >/dev/null 2>&1 || true
done

tail -n +2 "${PROVISION_DIR}/data/grupos.csv" | while IFS=';' read -r grupo _d extra; do
  [ -z "${extra}" ] && continue
  samba-tool group addmembers "${grupo}" "${extra}" -H ldap://127.0.0.1 "${ADM[@]}" >/dev/null 2>&1 || true
done

# --- 8. Delegação: GG_Helpdesk redefine senha e desbloqueia usuários -------------
# Só na OU Usuarios (não alcança administradores). GUIDs padrão do schema do AD:
#   00299570-...  = direito estendido "Reset Password"
#   28630ebf-...  = atributo lockoutTime (desbloquear conta)
#   bf967a0a-...  = atributo pwdLastSet (forçar troca no próximo logon)
#   bf967aba-...  = classe "user" (herda só para objetos usuário)
HELPDESK_SID="$(samba-tool group show GG_Helpdesk --attributes=objectSid -H ldap://127.0.0.1 "${ADM[@]}" | awk '/objectSid/ {print $2}')"
USERS_OU="OU=Usuarios,OU=CORP,${LAB_BASE_DN}"
USER_CLASS="bf967aba-0de6-11d0-a285-00aa003049e2"
for ace in \
  "(OA;CIIO;CR;00299570-246d-11d0-a768-00aa006e0529;${USER_CLASS};${HELPDESK_SID})" \
  "(OA;CIIO;RPWP;28630ebf-41d5-11d1-a9c1-0000f80367c1;${USER_CLASS};${HELPDESK_SID})" \
  "(OA;CIIO;RPWP;bf967a0a-0de6-11d0-a285-00aa003049e2;${USER_CLASS};${HELPDESK_SID})"; do
  samba-tool dsacl set --objectdn="${USERS_OU}" --sddl="${ace}" -H ldap://127.0.0.1 "${ADM[@]}" >/dev/null 2>&1 || true
done
log "delegação aplicada: GG_Helpdesk em ${USERS_OU}"

# --- 9. DHCP (Kea) ---------------------------------------------------------------
log "configurando DHCP (Kea) em ${LAN_IF}"
mkdir -p /run/kea /var/lib/kea
render "${PROVISION_DIR}/files/kea-dhcp4.conf.tpl" /etc/kea/kea-dhcp4.conf
kea-dhcp4 -t /etc/kea/kea-dhcp4.conf >/dev/null || die "configuração do Kea inválida"
systemctl enable kea-dhcp4-server >/dev/null 2>&1
systemctl restart kea-dhcp4-server
wait_for 30 "Kea DHCP ativo" systemctl is-active kea-dhcp4-server

# --- 10. NTP para o domínio --------------------------------------------------------
if ! is_container; then
  cat > /etc/chrony/conf.d/corp-lab-dc.conf <<EOF
# dc01 é a fonte de hora do domínio (Kerberos exige relógios sincronizados)
allow ${LAB_NET_CIDR}
ntpsigndsocket /var/lib/samba/ntp_signd
EOF
  chown root:_chrony /var/lib/samba/ntp_signd 2>/dev/null || true
  chmod 750 /var/lib/samba/ntp_signd 2>/dev/null || true
  systemctl restart chrony
fi

# --- 11. Backup diário do AD (02:30, guarda 7 cópias) ----------------------------
install -m 755 "${PROVISION_DIR}/files/bin/backup-dc"    /usr/local/sbin/backup-dc
install -m 755 "${PROVISION_DIR}/files/bin/restaurar-dc" /usr/local/sbin/restaurar-dc
cat > /etc/systemd/system/backup-dc.service <<'EOF'
[Unit]
Description=Backup a frio do controlador de domínio (AD + DHCP)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/backup-dc
EOF
cat > /etc/systemd/system/backup-dc.timer <<'EOF'
[Unit]
Description=Backup diário do dc01

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now backup-dc.timer >/dev/null 2>&1
log "backup diário agendado: backup-dc.timer (02:30), destino /var/backups/dc01"

ok "dc01 pronto: domínio ${LAB_REALM}, DNS ${DC01_IP}, DHCP ${DHCP_POOL_START}-${DHCP_POOL_END}"

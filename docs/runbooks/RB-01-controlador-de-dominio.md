# RB-01 — Controlador de domínio (dc01)

| | |
|---|---|
| **Objetivo** | Entender, montar à mão se preciso e verificar o controlador de domínio CORP.LAB |
| **Onde** | dc01 (`vagrant ssh dc01`, depois `sudo -i`) |
| **Automação** | [`provision/dc01.sh`](../../provision/dc01.sh) faz tudo abaixo sozinho |
| **Risco** | Alto se feito no DC de produção: o AD é a base de tudo |

## O que o dc01 faz

Active Directory (Samba AD DC) + DNS do domínio + DHCP (Kea) + fonte de hora (chrony) + backup diário. Veja o [inventário](../01-inventario.md#4-active-directory) para OUs, usuários e grupos.

## Montagem manual (o que o script faz, passo a passo)

> Use quando precisar montar um DC fora do laboratório ou entender um passo. No laboratório, prefira `vagrant provision dc01`.

**1. Nome e IP fixo.** O DC precisa de IP fixo e de saber o próprio nome completo.

```bash
hostnamectl set-hostname dc01
echo "10.10.10.10 dc01.corp.lab dc01" >> /etc/hosts
# IP fixo via netplan: veja /etc/netplan/60-corp-lan.yaml gerado pelo script
```

**2. Pacotes.**

```bash
apt install samba samba-ad-dc samba-ad-provision winbind libnss-winbind krb5-user \
            smbclient ldb-tools python3-samba kea-dhcp4-server chrony
```

**3. Desligar os serviços de "servidor comum"** (num DC quem atende é o `samba-ad-dc`):

```bash
systemctl disable --now smbd nmbd winbind
systemctl mask smbd nmbd winbind
rm -f /etc/samba/smb.conf
```

**4. Promover a controlador de domínio.**

```bash
samba-tool domain provision \
  --realm=CORP.LAB --domain=CORP --server-role=dc \
  --dns-backend=SAMBA_INTERNAL --host-ip=10.10.10.10 \
  --adminpass='<senha do Administrator>' \
  --option="dns forwarder = 10.0.2.3"
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
```

**5. O DC resolve nomes nele mesmo.**

```bash
systemctl disable --now systemd-resolved
rm -f /etc/resolv.conf
printf 'nameserver 127.0.0.1\nsearch corp.lab\n' > /etc/resolv.conf
```

**6. Ligar o serviço.**

```bash
systemctl unmask samba-ad-dc
systemctl enable --now samba-ad-dc
```

**7. Estrutura e política** — OUs, grupos, usuários e política de senha: [RB-04](RB-04-usuarios-e-grupos.md). DNS: [RB-02](RB-02-dns.md). DHCP: [RB-03](RB-03-dhcp.md).

**8. Hora do domínio** (Kerberos recusa login com relógio mais de 5 min fora):

```bash
cat > /etc/chrony/conf.d/corp-lab-dc.conf <<'EOF'
allow 10.10.10.0/24
ntpsigndsocket /var/lib/samba/ntp_signd
EOF
chown root:_chrony /var/lib/samba/ntp_signd && chmod 750 /var/lib/samba/ntp_signd
systemctl restart chrony
```

## Verificação de saúde

Tudo de uma vez: `sudo /opt/homelab/tests/dc-checks.sh`. Ou à mão:

```bash
systemctl status samba-ad-dc --no-pager          # active (running)
samba-tool domain info 127.0.0.1                  # domínio, DC, site
samba-tool fsmo show -U Administrator             # dc01 dono de todas as funções FSMO
samba-tool dbcheck --cross-ncs                    # "0 errors"
host -t SRV _ldap._tcp.corp.lab 127.0.0.1         # aponta para dc01.corp.lab
kinit Administrator && klist                      # Kerberos emitindo ticket
```

## Onde ficam as coisas

| O quê | Caminho |
|---|---|
| Configuração do Samba | `/etc/samba/smb.conf` |
| Banco do AD | `/var/lib/samba/private/sam.ldb` (+ `sam.ldb.d/`) |
| SYSVOL (GPOs e scripts de logon) | `/var/lib/samba/sysvol/corp.lab/` |
| Log principal (inclui auditoria de login) | `/var/log/samba/log.samba` |
| Log da promoção | `/var/log/samba-provision.log` |
| Backups | `/var/backups/dc01/` — [RB-08](RB-08-backup-e-restauracao.md) |

## Gerenciar pelo Windows (RSAT)

Uma estação Windows no domínio com RSAT instalado gerencia este DC com as ferramentas de sempre: **Usuários e Computadores do Active Directory**, **DNS** e **Gerenciamento de Política de Grupo**. Passo a passo em [RB-07](RB-07-estacao-windows.md#5-gerenciar-o-ad-pelo-windows-rsat).

## Se der errado

- Serviço não sobe: `journalctl -u samba-ad-dc -n 50 --no-pager` e `tail -50 /var/log/samba/log.samba`.
- Porta 53 ocupada (`Failed to bind to 0.0.0.0:53`): o `systemd-resolved` voltou — repita o passo 5.
- Login falha para todo mundo: confira a hora (`chronyc tracking`) — [TS-03](../troubleshooting/TS-03-usuario-nao-consegue-logar.md).

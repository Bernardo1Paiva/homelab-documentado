# RB-02 — DNS do domínio

| | |
|---|---|
| **Objetivo** | Consultar, criar e remover registros DNS da zona `corp.lab` |
| **Onde** | dc01 (`vagrant ssh dc01` → `sudo -i`) ou console **DNS** do RSAT no Windows |
| **Automação** | registros fixos em [`provision/dc01.sh`](../../provision/dc01.sh) (seção 3) |
| **Risco** | Médio: apagar um registro SRV do AD derruba o login de todo mundo |

> Por que isso importa: no AD, **tudo começa pelo DNS**. A estação acha o controlador de domínio perguntando ao DNS pelos registros `_ldap._tcp.corp.lab` e `_kerberos._tcp.corp.lab`. DNS errado = "o domínio não está disponível".

Nos comandos abaixo, `-U Administrator` pede a senha do domínio (ou use `-U 'Administrator%<senha>'`).

## Consultar

```bash
dig dc01.corp.lab +short                      # nome → IP
dig -x 10.10.10.20 +short                     # IP → nome (reverso)
dig _ldap._tcp.corp.lab SRV +short            # onde está o DC
samba-tool dns query 127.0.0.1 corp.lab @ ALL -U Administrator     # todos os registros da zona
```

No Windows: `nslookup fs01.corp.lab` e `nslookup -type=SRV _ldap._tcp.corp.lab`.

## Criar um servidor novo (A + PTR)

Exemplo: `srv-app01` com IP `10.10.10.40`.

```bash
samba-tool dns add 127.0.0.1 corp.lab srv-app01 A 10.10.10.40 -U Administrator
samba-tool dns add 127.0.0.1 10.10.10.in-addr.arpa 40 PTR srv-app01.corp.lab -U Administrator
```

Depois: inclua o host no [inventário](../01-inventario.md) e, para ficar permanente no laboratório, uma linha `dns_add` no `dc01.sh`.

## Criar um apelido (CNAME)

```bash
samba-tool dns add 127.0.0.1 corp.lab intranet CNAME srv-app01.corp.lab -U Administrator
```

## Remover

```bash
samba-tool dns delete 127.0.0.1 corp.lab srv-app01 A 10.10.10.40 -U Administrator
samba-tool dns delete 127.0.0.1 10.10.10.in-addr.arpa 40 PTR srv-app01.corp.lab -U Administrator
```

> ⚠️ Nunca apague registros que começam com `_` (SRV do AD) nem as zonas `_msdcs`, `DomainDnsZones`, `ForestDnsZones`.

## Encaminhador (nomes da internet)

O dc01 responde `corp.lab` e encaminha o resto para `10.0.2.3` (NAT do VirtualBox). Para trocar (ex.: `1.1.1.1`):

```bash
sed -i 's/^\s*dns forwarder = .*/\tdns forwarder = 1.1.1.1/' /etc/samba/smb.conf
systemctl restart samba-ad-dc
dig google.com @127.0.0.1 +short
```

## Como confirmar

Da ws01: `dig <nome>.corp.lab +short` retorna o IP certo, e `sudo /opt/homelab/tests/smoke-test.sh` passa a seção **1. DNS**.

## Se der errado

[TS-02 — Nome não resolve](../troubleshooting/TS-02-nome-nao-resolve.md).

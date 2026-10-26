# RB-05 — Servidor de arquivos (fs01)

| | |
|---|---|
| **Objetivo** | Criar compartilhamentos, dar e tirar acesso, conferir permissões |
| **Onde** | fs01 (`vagrant ssh fs01` → `sudo -i`) |
| **Automação** | [`provision/fs01.sh`](../../provision/fs01.sh) + [`compartilhamentos.csv`](../../provision/data/compartilhamentos.csv) |
| **Risco** | Médio: permissão errada expõe dados (RH, Financeiro) |

## Como as permissões funcionam aqui

Duas camadas, e é importante saber qual faz o quê:

| Camada | Onde | Faz o quê |
|---|---|---|
| **Compartilhamento** | `/etc/samba/shares.conf` (`valid users`) | Decide **quem pode conectar** (e quem nem enxerga a pasta) |
| **Pasta (ACL)** | `getfacl /srv/compartilhamentos/<pasta>` | Decide **o que cada grupo pode fazer**: ler (`r-x`) ou ler e gravar (`rwx`). As permissões de vários grupos **se somam** |

Por que não usar `read list` no compartilhamento? Ela **vence** a ACL e tira a escrita de quem está num grupo de escrita e também num de leitura. Caso real em [TS-04](../troubleshooting/TS-04-acesso-negado-na-pasta.md#caso-real-o-coordenador-que-não-conseguia-gravar).

## 1. Dar acesso a alguém

Coloque a pessoa no **grupo** certo ([RB-04](RB-04-usuarios-e-grupos.md)). Não mexa na pasta para uma pessoa só. Ela precisa fazer **logoff/logon** para valer.

## 2. Criar um compartilhamento novo

**Jeito permanente (laboratório):** adicione uma linha no `compartilhamentos.csv` e reprovisione:

```text
Juridico;GG_Juridico;GG_Diretoria;Contratos e processos (Diretoria só lê)
```

```bash
vagrant provision fs01          # (no host)
```

**Jeito manual (no servidor):**

```bash
D=/srv/compartilhamentos/Juridico
mkdir -p $D
chown root:"domain admins" $D && chmod 2770 $D
setfacl -m  "g:domain admins:rwx,g:GG_Juridico:rwx,g:GG_Diretoria:rx" $D
setfacl -dm "g:domain admins:rwx,g:GG_Juridico:rwx,g:GG_Diretoria:rx,u::rwx,g::rwx,o::---" $D

cat >> /etc/samba/shares.conf <<'EOF'

[Juridico]
   comment = Contratos e processos (Diretoria só lê)
   path = /srv/compartilhamentos/Juridico
   read only = no
   valid users = @"GG_Juridico" @"domain admins" @"GG_Diretoria"
   inherit acls = yes
   create mask = 0660
   directory mask = 2770
EOF

testparm -s > /dev/null && smbcontrol smbd reload-config
```

- `-m` aplica na pasta; `-dm` é a permissão **padrão** que os arquivos novos herdam (sem ela, arquivo criado por um usuário fica invisível para o colega).
- O grupo precisa existir no AD antes ([RB-04 §7](RB-04-usuarios-e-grupos.md#7-criar-um-grupo-novo)).
- Atualize o [inventário](../01-inventario.md#5-compartilhamentos-fs01).

## 3. Conferir permissões

```bash
getfacl -p /srv/compartilhamentos/Financeiro          # quem pode o quê na pasta
testparm -s --section-name=Financeiro 2>/dev/null     # regras do compartilhamento
id bruno.lima                                         # grupos que o fs01 enxerga para a pessoa
smbstatus                                             # quem está conectado agora e com quais arquivos abertos
```

## 4. Acessar as pastas

| De onde | Como |
|---|---|
| Windows do domínio | Explorador → `\\fs01.corp.lab\Financeiro`, ou `net use Z: \\fs01.corp.lab\Publico /persistent:yes` |
| ws01 (Linux) | `kinit bruno.lima` e depois `smbclient //fs01.corp.lab/Financeiro --use-kerberos=required` |

Use o nome completo (`fs01.corp.lab`) ou o apelido `arquivos.corp.lab`: com IP, o Windows não usa Kerberos.

## 5. Saúde do servidor

```bash
net ads testjoin            # "Join is OK" — fs01 continua no domínio
wbinfo -t                   # canal seguro com o DC OK
wbinfo -u | head            # enxerga os usuários do AD
systemctl status smbd winbind --no-pager
tail -50 /var/log/samba/log.smbd
```

## Como confirmar

Da ws01: `sudo /opt/homelab/tests/smoke-test.sh` — a seção **4. Compartilhamentos e permissões** testa grava/lê/negado com usuários de cada grupo.

## Se der errado

[TS-04 — Acesso negado na pasta](../troubleshooting/TS-04-acesso-negado-na-pasta.md).

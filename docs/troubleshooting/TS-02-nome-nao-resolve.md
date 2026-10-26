# TS-02 — Nome não resolve / "o domínio não está disponível"

**Sintoma.** `ping fs01.corp.lab` diz que o host não foi encontrado; o Windows diz "Não foi possível contatar um controlador de domínio"; `realm discover corp.lab` falha; alerta `DnsDoDominioFalhando`.

**Por que é tão grave:** a estação encontra o controlador de domínio **pelo DNS** (registros SRV). Sem DNS certo, não há login, nem pasta, nem GPO — mesmo com a rede "funcionando".

## Diagnóstico

| # | Pergunta | Comando (na estação) | Esperado |
|---|---|---|---|
| 1 | Quem é meu DNS? | Win: `ipconfig /all` · Linux: `resolvectl status` | **10.10.10.10** (e só ele para `corp.lab`) |
| 2 | O DC responde? | `ping 10.10.10.10` | responde |
| 3 | O DNS do DC responde? | `nslookup dc01.corp.lab 10.10.10.10` · `dig @10.10.10.10 dc01.corp.lab` | 10.10.10.10 |
| 4 | Os registros do AD existem? | `nslookup -type=SRV _ldap._tcp.corp.lab` · `dig _ldap._tcp.corp.lab SRV` | `dc01.corp.lab` |
| 5 | O nome procurado existe? | no dc01: `samba-tool dns query 127.0.0.1 corp.lab <nome> ALL -U Administrator` | o registro |

Interpretação: se o **3 funciona** mas o nome simples falha, o problema é o **DNS configurado na estação** (passo 1). Se o **3 falha**, o problema é **no dc01**.

## Causas comuns e correção

| Causa | Como reconhecer | Correção |
|---|---|---|
| Estação usando DNS do roteador/Google (8.8.8.8) | passo 1 mostra outro servidor | A estação deve usar **só** o DNS do AD. Pegue IP pelo DHCP ([TS-01](TS-01-estacao-sem-ip.md)) ou corrija o IP fixo. *Nunca* coloque 8.8.8.8 como DNS secundário de máquina do domínio: ela vai perguntar ao Google por `corp.lab` e falhar aleatoriamente |
| `samba-ad-dc` parado | no dc01: `systemctl is-active samba-ad-dc` | `systemctl restart samba-ad-dc` · log: `tail -50 /var/log/samba/log.samba` |
| Porta 53 ocupada no dc01 | log com `Failed to bind ... :53` | `systemctl disable --now systemd-resolved` e refaça o `/etc/resolv.conf` — [RB-01 passo 5](../runbooks/RB-01-controlador-de-dominio.md#montagem-manual-o-que-o-script-faz-passo-a-passo) |
| Registro não existe / IP errado | passo 5 vazio ou com IP antigo | Crie/corrija — [RB-02](../runbooks/RB-02-dns.md) |
| Cache velho na estação | o dc01 já responde certo (passo 3), a estação não | Win: `ipconfig /flushdns` · Linux: `resolvectl flush-caches` |
| Nome da internet não resolve (só `corp.lab` funciona) | `dig @10.10.10.10 google.com` falha | Encaminhador errado/inacessível — [RB-02 §Encaminhador](../runbooks/RB-02-dns.md#encaminhador-nomes-da-internet) |

## Como confirmar

`nslookup -type=SRV _ldap._tcp.corp.lab` responde `dc01.corp.lab`; no mon01, `alertas` sem `DnsDoDominioFalhando`; seção **1. DNS** do teste de fumaça passa.

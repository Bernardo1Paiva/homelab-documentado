# TS-01 — Estação sem IP (ou com IP 169.254.x.x)

**Sintoma.** A estação não navega nem acessa nada da rede. No Windows, `ipconfig` mostra **169.254.x.x** (o Windows inventou um IP porque ninguém respondeu ao DHCP). No Linux, a placa da `corp-lan` fica sem `inet 10.10.10.x`.

## Diagnóstico (do mais rápido ao mais demorado)

| # | Verifique | Comando | Esperado |
|---|---|---|---|
| 1 | A placa está na rede certa? | VirtualBox → Configurações da VM → Rede | "Rede Interna", nome **`corp-lan`** (erro de digitação = rede diferente!) |
| 2 | O cabo virtual está conectado? | mesma tela → "Cabo conectado" marcado | marcado |
| 3 | O DHCP está rodando? | no dc01: `systemctl is-active kea-dhcp4-server` | `active` |
| 4 | O DHCP recebeu o pedido? | no dc01: `journalctl -u kea-dhcp4-server -n 30` | linhas `DHCP4_LEASE_ALLOC` com o MAC da estação |
| 5 | O escopo está cheio? | no dc01: `tail -n +2 /var/lib/kea/kea-leases4.csv \| cut -d, -f1 \| sort -u \| wc -l` | bem menos de 100 IPs já entregues |
| 6 | O monitoramento acusou? | no mon01: `alertas` | sem `ServicoParado ... kea-dhcp4-server` |

Para forçar um novo pedido: Windows `ipconfig /release && ipconfig /renew` · Linux `sudo networkctl reconfigure <placa>`.

## Causas comuns e correção

| Causa | Como reconhecer | Correção |
|---|---|---|
| Kea parado | passo 3 = `inactive`/`failed` | `systemctl restart kea-dhcp4-server`; se não subir, `kea-dhcp4 -t /etc/kea/kea-dhcp4.conf` mostra o erro de configuração — [RB-03](../runbooks/RB-03-dhcp.md) |
| Configuração do Kea editada com erro | `kea-dhcp4 -t` acusa linha | Volte o `.bak` ou rode `vagrant provision dc01` (regera do template validado) |
| VM em outra rede interna | passo 1 diferente de `corp-lan` | Corrija o nome da rede interna |
| Escopo esgotado | passo 4 mostra `DHCP4_ALLOC_FAIL` / *no addresses available* | Amplie o escopo ou reduza o tempo de concessão — [RB-03](../runbooks/RB-03-dhcp.md#aumentar-o-escopo) |
| Kea escutando na placa errada | log do Kea sem nenhum pedido; `grep interfaces /etc/kea/kea-dhcp4.conf` mostra placa que não é a da `corp-lan` | `vagrant provision dc01` (o script descobre a placa pelo MAC) |
| dc01 desligado | `vagrant status` | `vagrant up dc01` |

## Como confirmar

Estação com IP entre 10.10.10.100 e .199, DNS 10.10.10.10 e sufixo `corp.lab`. Na ws01: `sudo /opt/homelab/tests/smoke-test.sh` passa a seção **2. DHCP**.

## Registro no chamado

Anote: MAC da estação, horário, causa encontrada, o que foi feito. Se foi o Kea que parou, investigue o **porquê** (`journalctl -u kea-dhcp4-server --since "-2h"`) antes de fechar.

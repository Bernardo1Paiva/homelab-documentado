# RB-03 — DHCP (Kea)

| | |
|---|---|
| **Objetivo** | Ver concessões, criar reservas e alterar o escopo do DHCP |
| **Onde** | dc01 (`vagrant ssh dc01` → `sudo -i`) |
| **Automação** | [`provision/files/kea-dhcp4.conf.tpl`](../../provision/files/kea-dhcp4.conf.tpl) + parâmetros em [`lab.env`](../../provision/lab.env) |
| **Risco** | Alto: configuração inválida = estações sem IP. Por isso **sempre** valide com `kea-dhcp4 -t` antes de reiniciar |

## Configuração atual

| Item | Valor |
|---|---|
| Interface | placa da rede `corp-lan` do dc01 |
| Escopo | 10.10.10.100 – 10.10.10.199 |
| Concessão | 8 horas (renova com 4 h) |
| Opções entregues | DNS 10.10.10.10 · domínio `corp.lab` · busca `corp.lab` · NTP 10.10.10.10 |
| Reservas | impressora01 → 10.10.10.50 |
| Arquivos | config `/etc/kea/kea-dhcp4.conf` · concessões `/var/lib/kea/kea-leases4.csv` |

## Ver quem pegou IP

```bash
column -t -s, /var/lib/kea/kea-leases4.csv | cut -c1-120
journalctl -u kea-dhcp4-server --since "1 hour ago" | grep -E "LEASE_ALLOC|LEASE_ADVERT"
```

Cada linha de `DHCP4_LEASE_ALLOC` mostra MAC e IP entregue — útil para achar "qual máquina está com tal IP".

## Criar uma reserva (IP fixo por MAC)

Use para impressoras, relógio de ponto, câmeras: equipamentos que precisam de IP previsível mas não se configuram bem com IP fixo manual. Faixa de reservas: **10.10.10.50 – 99**.

**Jeito permanente (laboratório):** acrescente a reserva no bloco `"reservations"` do template e reprovisione:

```json
{ "hw-address": "08:00:27:aa:00:51", "ip-address": "10.10.10.51", "hostname": "relogio-ponto" }
```

```bash
vagrant provision dc01     # (no host) — gera, valida e aplica
```

**Jeito manual (no servidor):**

```bash
cp /etc/kea/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf.bak-$(date +%F)
nano /etc/kea/kea-dhcp4.conf               # adicione a reserva
kea-dhcp4 -t /etc/kea/kea-dhcp4.conf       # TEM que dizer que está OK
systemctl restart kea-dhcp4-server
systemctl is-active kea-dhcp4-server
```

Crie também o registro DNS do equipamento ([RB-02](RB-02-dns.md)) e atualize o [inventário](../01-inventario.md#2-plano-de-endereçamento-ip).

## Aumentar o escopo

Altere `DHCP_POOL_START` / `DHCP_POOL_END` no `lab.env` (respeitando o [plano de endereçamento](../01-inventario.md#2-plano-de-endereçamento-ip)) e rode `vagrant provision dc01`.

## No cliente

| Sistema | Liberar e pedir IP de novo | Ver o que recebeu |
|---|---|---|
| Windows | `ipconfig /release` e `ipconfig /renew` | `ipconfig /all` |
| ws01 (Linux) | `sudo networkctl reconfigure <placa>` | `ip -4 addr` e `resolvectl status` |

## Como confirmar

Da ws01: `sudo /opt/homelab/tests/smoke-test.sh` passa a seção **2. DHCP** (ele faz um pedido DHCP real e confere IP, DNS e domínio recebidos).

## Se der errado

- Kea não sobe depois de editar: `kea-dhcp4 -t /etc/kea/kea-dhcp4.conf` mostra a linha do erro; restaure o `.bak`.
- Estação sem IP: [TS-01](../troubleshooting/TS-01-estacao-sem-ip.md).

# RB-06 — Monitoramento (mon01)

| | |
|---|---|
| **Objetivo** | Saber se está tudo no ar, incluir algo novo no monitoramento e lidar com alertas |
| **Onde** | Navegador do host (<http://localhost:9090>, <http://localhost:9093>) ou mon01 (`vagrant ssh mon01` → `sudo -i`) |
| **Automação** | [`provision/mon01.sh`](../../provision/mon01.sh) e [`provision/files/`](../../provision/files/) (`prometheus.yml.tpl`, `blackbox.yml.tpl`, `alertas.yml`, `alertmanager.yml`) |

## Como funciona (em 30 segundos)

```
 dc01, fs01, mon01 ──(node_exporter :9100: CPU, RAM, disco, serviços)──┐
                                                                       ├─► Prometheus ──(regras)──► Alertmanager ──► equipe
 Blackbox (no mon01) ──(ping, portas 88/389/445, consulta DNS)─────────┘    a cada 15 s
```

- **node_exporter** = a máquina conta como está por dentro.
- **Blackbox** = o mon01 testa de fora, como um usuário veria ("a porta do SMB responde?").
- **Prometheus** coleta tudo a cada 15 s e avalia as [regras de alerta](../../provision/files/alertas.yml).
- **Alertmanager** agrupa, evita repetição (e evita o "efeito cascata": se a máquina caiu, não manda também um alerta por porta dela) e entrega.

## 1. Está tudo no ar?

No navegador: <http://localhost:9090/targets> — tudo **UP** em verde. Ou no mon01:

```bash
alvos       # cada alvo e se está UP ou DOWN, com o erro se houver
alertas     # alertas ativos (vazio = nenhum)
```

Exemplo de saída real: [evidencias/monitoramento-alvos.txt](../evidencias/monitoramento-alvos.txt).

## 2. Os alertas

| Alerta | Dispara quando | Gravidade | O que fazer |
|---|---|---|---|
| `MaquinaFora` | node_exporter não responde por 1 min | crítica | [TS-05 §MaquinaFora](../troubleshooting/TS-05-alerta-disparou.md#maquinafora) |
| `SemPing` | sem resposta de ping por 1 min | crítica | [TS-05 §SemPing](../troubleshooting/TS-05-alerta-disparou.md#semping) |
| `PortaDeServicoFechada` | Kerberos/LDAP/SMB recusando conexão por 1 min | crítica | [TS-05 §Porta](../troubleshooting/TS-05-alerta-disparou.md#portadeservicofechada) |
| `DnsDoDominioFalhando` | DNS não responde o SRV do AD por 1 min | crítica | [TS-02](../troubleshooting/TS-02-nome-nao-resolve.md) |
| `ServicoParado` | serviço crítico da máquina parado por 30 s | crítica | [TS-05 §ServicoParado](../troubleshooting/TS-05-alerta-disparou.md#servicoparado) |
| `DiscoQuaseCheio` | menos de 15% livre por 5 min | aviso | [TS-05 §Disco](../troubleshooting/TS-05-alerta-disparou.md#discoquasecheio) |
| `MemoriaAlta` | memória acima de 90% por 10 min | aviso | [TS-05 §Memória](../troubleshooting/TS-05-alerta-disparou.md#memoriaalta) |

Estados: **PENDING** = condição verdadeira, mas ainda esperando o tempo mínimo (evita alarme falso por um soluço de rede). **FIRING** = disparado.

Teste de ponta a ponta (derruba o DHCP de propósito e confere): `bash tests/alert-drill.sh` — resultado real em [evidencias/simulacao-alerta.log](../evidencias/simulacao-alerta.log).

## 3. Manutenção programada (silenciar)

Antes de reiniciar o dc01 de propósito, silencie para não gerar alarme falso:

```bash
amtool silence add alertname=~".+" host=dc01 --duration=1h \
  --author="bernardo" --comment="Atualização do dc01 — chamado #123" \
  --alertmanager.url=http://localhost:9093

amtool silence query --alertmanager.url=http://localhost:9093                  # silêncios ativos
amtool silence expire <ID> --alertmanager.url=http://localhost:9093            # encerrar antes da hora
```

Também dá pela interface: <http://localhost:9093> → **New Silence**.

## 4. Monitorar uma máquina nova

Exemplo: servidor `srv-app01` (10.10.10.40) com node_exporter.

1. No servidor novo: `apt install prometheus-node-exporter`.
2. Em [`prometheus.yml.tpl`](../../provision/files/prometheus.yml.tpl), acrescente nos jobs `node` e `ping`:

   ```yaml
         - targets: ["srv-app01.{{LAB_DOMAIN}}:9100"]
           labels: { host: srv-app01, papel: aplicacao }
   ```

   ```yaml
         - targets: ["10.10.10.40"]
           labels: { host: srv-app01 }
   ```

3. Aplique: `vagrant provision mon01` (gera, valida com `promtool` e reinicia). À mão no mon01:

   ```bash
   nano /etc/prometheus/prometheus.yml
   promtool check config /etc/prometheus/prometheus.yml
   curl -X POST http://localhost:9090/-/reload
   alvos | grep srv-app01
   ```

> Todo alvo leva o rótulo `host`. É ele que faz o Alertmanager entender que vários alertas são "da mesma máquina".

## 5. Receber alertas por e-mail

No [`alertmanager.yml`](../../provision/files/alertmanager.yml), descomente e preencha o bloco `email_configs` (servidor SMTP, usuário, senha de app). Valide e reinicie:

```bash
amtool check-config /etc/prometheus/alertmanager.yml
systemctl restart prometheus-alertmanager
```

O Alertmanager também entrega para Microsoft Teams, Slack, Telegram e webhooks — mesmo arquivo, outro bloco de `receivers`.

## 6. Consultas rápidas (PromQL)

Em <http://localhost:9090/graph>:

| Pergunta | Consulta |
|---|---|
| Quem está fora? | `up == 0` |
| % de disco livre por máquina | `100 * node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}` |
| Uso de CPU | `100 - avg by (host) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| Tempo de resposta do DNS | `probe_duration_seconds{job="dns"}` |
| Serviços parados | `node_systemd_unit_state{state="active"} == 0` |

## Se der errado

- Prometheus não sobe depois de editar: `promtool check config /etc/prometheus/prometheus.yml` aponta a linha; `journalctl -u prometheus -n 30`.
- Alvo DOWN com `connection refused`: o exporter não está rodando no alvo (`systemctl status prometheus-node-exporter` lá).
- Alvo DOWN com `no such host`: problema de DNS ([TS-02](../troubleshooting/TS-02-nome-nao-resolve.md)).

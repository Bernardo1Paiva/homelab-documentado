# TS-05 — Um alerta disparou

Ordem geral para qualquer alerta:

1. **Confirmar** no mon01: `alertas` (o que está disparado) e `alvos` (o que está DOWN).
2. **Avaliar o impacto** com a [leitura de impacto](../02-diagrama-de-rede.md#leitura-de-impacto): quem está parado agora?
3. **Corrigir** com a seção do alerta abaixo.
4. **Confirmar que resolveu**: o alerta some de `alertas` em até ~1 min.
5. **Registrar**: horário de início e fim, causa, correção. Se aconteceu mais de uma vez, abra um problema para tratar a causa raiz.

---

## MaquinaFora

O Prometheus não consegue coletar o node_exporter da máquina há 1 minuto.

| Verifique | Como | Correção |
|---|---|---|
| A VM está ligada? | host: `vagrant status` | `vagrant up <vm>` |
| Responde ping? (`SemPing` junto?) | mon01: `ping -c2 <ip>` | Se não responde: VM travada → `vagrant reload <vm>` |
| Responde ping mas não as métricas | na VM: `systemctl status prometheus-node-exporter` | `systemctl restart prometheus-node-exporter` |

> Com a máquina fora, o Alertmanager **segura** os alertas de porta e serviço dela (regra de inibição) para não lotar a caixa da equipe com 5 avisos do mesmo problema.

## SemPing

Sem resposta ICMP há 1 min. Se veio sozinho (sem `MaquinaFora`), costuma ser rede: confira a placa `corp-lan` da VM (`ip -br addr` na VM) e se o cabo virtual está conectado no VirtualBox.

## PortaDeServicoFechada

A porta responde "recusado" ou não responde. O rótulo `servico` diz qual:

| servico | Porta | Serviço no host | Correção |
|---|---|---|---|
| kerberos / ldap / smb-dc | 88 / 389 / 445 no dc01 | `samba-ad-dc` | `systemctl restart samba-ad-dc` · `tail -50 /var/log/samba/log.samba` |
| smb-arquivos | 445 no fs01 | `smbd` | `systemctl restart smbd` · `tail -50 /var/log/samba/log.smbd` |

## ServicoParado

O rótulo `name` diz o serviço e `host` diz a máquina.

```bash
systemctl status <servico> --no-pager       # por que parou?
journalctl -u <servico> -n 50 --no-pager    # últimas mensagens
systemctl restart <servico>
systemctl is-active <servico>
```

**Não pare em "reiniciei e voltou".** Leia o log: configuração editada com erro? disco cheio? falta de memória (`dmesg | grep -i oom`)?

Simulação real (Kea parado de propósito pelo [`alert-drill.sh`](../../tests/alert-drill.sh)): o alerta passou a PENDING em ~5–15 s e a FIRING em 35–45 s, chegou ao Alertmanager e resolveu sozinho ~15 s após religar o serviço — [evidencias/simulacao-alerta.log](../evidencias/simulacao-alerta.log).

## DiscoQuaseCheio

```bash
df -h                                                    # qual partição
du -xh / 2>/dev/null | sort -rh | head -15               # o que está ocupando
journalctl --disk-usage                                  # logs do sistema
```

| Vilão comum | Correção |
|---|---|
| Logs do journal | `journalctl --vacuum-size=200M` |
| Pacotes antigos em cache | `apt clean` |
| Backups acumulando (dc01) | o `backup-dc` já guarda só 7; confira `/var/backups/dc01/antes-restauracao-*` antigos |
| Arquivos dos usuários (fs01) | avise os donos da área; avalie cota ou aumentar o disco |

## MemoriaAlta

```bash
free -h
ps aux --sort=-%mem | head -10
dmesg | grep -i "out of memory"
```

Se for um serviço vazando memória, reinicie-o e registre. Se for uso legítimo, aumente a memória da VM (`memory` no `Vagrantfile`, depois `vagrant reload <vm>`).

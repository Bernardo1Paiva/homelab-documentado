# Evidências

Saídas **reais** dos testes e do estado do ambiente, gravadas pelos scripts (nada aqui foi digitado à mão).

| Arquivo | Gerado por | Mostra |
|---|---|---|
| [smoke-test.log](smoke-test.log) | `tests/smoke-test.sh` na ws01 | 30 verificações: DNS, DHCP, domínio, Kerberos, permissões, monitoramento |
| [dc-checks.log](dc-checks.log) | `tests/dc-checks.sh` no dc01 | Saúde do AD, política de senha, delegação do Helpdesk |
| [simulacao-alerta.log](simulacao-alerta.log) | `tests/alert-drill.sh` | DHCP derrubado de propósito → alerta → resolução |
| [teste-restauracao-backup.log](teste-restauracao-backup.log) | `tests/backup-drill.sh` | Backup → usuário apagado → restauração → usuário de volta |
| [ad-usuarios-grupos.txt](ad-usuarios-grupos.txt) | `tests/coletar-evidencias.sh` | Domínio, OUs, usuários, grupos, computadores, política de senha |
| [dns-registros.txt](dns-registros.txt) | `tests/coletar-evidencias.sh` | Zonas e registros DNS |
| [dhcp-concessoes.txt](dhcp-concessoes.txt) | `tests/coletar-evidencias.sh` | Escopo ativo e concessões |
| [arquivos-permissoes.txt](arquivos-permissoes.txt) | `tests/coletar-evidencias.sh` | Compartilhamentos e ACLs das pastas |
| [monitoramento-alvos.txt](monitoramento-alvos.txt) | `tests/coletar-evidencias.sh` | Alvos UP/DOWN, alertas ativos, regras carregadas |

## De onde vieram

Esta versão foi gerada pelo **laboratório em contêineres** ([`tests/container-lab/run-lab.sh all`](../../tests/container-lab/run-lab.sh)), que roda os mesmos scripts de `provision/` usados nas VMs. Por isso:

- a ws01 aparece com IP fixo **10.10.10.90** (no contêiner o Docker dá o IP; a sonda de DHCP do teste recebe uma oferta real do Kea no escopo .100–.199);
- não há chrony (o relógio do contêiner é o do host).

Nas VMs do VirtualBox, gere a sua versão (na pasta do projeto, Git Bash) e faça commit:

```bash
vagrant ssh ws01 -c "sudo /opt/homelab/tests/smoke-test.sh" > docs/evidencias/smoke-test.log
vagrant ssh dc01 -c "sudo /opt/homelab/tests/dc-checks.sh"  > docs/evidencias/dc-checks.log
bash tests/alert-drill.sh        | tee docs/evidencias/simulacao-alerta.log
bash tests/backup-drill.sh       | tee docs/evidencias/teste-restauracao-backup.log
bash tests/coletar-evidencias.sh
```

Capturas de tela que valem acrescentar aqui: `localhost:9090/targets` com tudo UP, o alerta disparado durante a simulação em `localhost:9093` e, se fizer o [RB-07](../runbooks/RB-07-estacao-windows.md), o Windows logado como `CORP\ana.souza` com as unidades mapeadas.

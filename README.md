# Homelab CORP.LAB — infraestrutura de uma pequena empresa, documentada como produção

[![Testa o laboratório](https://github.com/Bernardo1Paiva/homelab-documentado/actions/workflows/laboratorio.yml/badge.svg)](https://github.com/Bernardo1Paiva/homelab-documentado/actions/workflows/laboratorio.yml)

Laboratório virtual que imita a TI de uma empresa de ~10 pessoas: **domínio Active Directory, DNS, DHCP, servidor de arquivos com permissões por departamento, monitoramento com alertas e backup testado** — tudo sobe com um comando no VirtualBox e está documentado para que outro técnico assuma o ambiente lendo só este repositório.

![Diagrama de rede](docs/img/diagrama-rede.svg)

## O que tem aqui

| Peça | Implementação | Detalhe |
|---|---|---|
| **Rede** | Rede interna `corp-lan` 10.10.10.0/24, plano de endereçamento por faixas | [Inventário §2](docs/01-inventario.md#2-plano-de-endereçamento-ip) |
| **Domínio** | Active Directory `CORP.LAB` (Samba AD DC) com OUs por departamento | [RB-01](docs/runbooks/RB-01-controlador-de-dominio.md) |
| **DNS** | Zona integrada ao AD + zona reversa + apelidos | [RB-02](docs/runbooks/RB-02-dns.md) |
| **DHCP** | Kea: escopo .100–.199, entrega DNS/domínio/NTP, reserva por MAC | [RB-03](docs/runbooks/RB-03-dhcp.md) |
| **Usuários** | 7 usuários, 6 grupos, política de senha e bloqueio, **delegação de Helpdesk** (reset de senha sem ser admin) | [RB-04](docs/runbooks/RB-04-usuarios-e-grupos.md) |
| **Arquivos** | 5 compartilhamentos com permissão por grupo; quem não tem acesso nem vê a pasta | [RB-05](docs/runbooks/RB-05-servidor-de-arquivos.md) |
| **Monitoramento** | Prometheus + Blackbox + Alertmanager, 12 alvos, 7 alertas — cada alerta aponta para o runbook que resolve | [RB-06](docs/runbooks/RB-06-monitoramento.md) |
| **Backup** | Backup diário do AD com retenção de 7 dias e **restauração testada** | [RB-08](docs/runbooks/RB-08-backup-e-restauracao.md) |
| **Estação** | Cliente Linux no domínio (automático) e Windows no domínio (passo a passo) | [RB-07](docs/runbooks/RB-07-estacao-windows.md) |

## Começo rápido

No Windows, com [VirtualBox 7.2](https://www.virtualbox.org/) e [Vagrant 2.4.9+](https://developer.hashicorp.com/vagrant) instalados (`winget install --id Oracle.VirtualBox -e` e `winget install --id Hashicorp.Vagrant -e`):

```bash
git clone https://github.com/Bernardo1Paiva/homelab-documentado.git
cd homelab-documentado
vagrant up                                                     # ~20 min na primeira vez
vagrant ssh ws01 -c "sudo /opt/homelab/tests/smoke-test.sh"    # 30 verificações
```

Depois abra <http://localhost:9090/targets> no navegador. Passo a passo completo, requisitos e problemas comuns: **[RB-00 — Subir o laboratório](docs/runbooks/RB-00-subir-o-laboratorio.md)**.

| Máquina | IP | Papel |
|---|---|---|
| dc01 | 10.10.10.10 | Controlador de domínio, DNS, DHCP, NTP |
| fs01 | 10.10.10.20 | Servidor de arquivos |
| mon01 | 10.10.10.30 | Monitoramento |
| ws01 | DHCP | Estação de funcionário |

## Documentação

**Para entender o ambiente**

- [01 — Inventário](docs/01-inventario.md): máquinas, IPs, DNS, OUs, usuários, grupos, pastas, portas, contas, rotinas
- [02 — Diagrama de rede](docs/02-diagrama-de-rede.md): topologia, dependências e "se cair, o que para"
- [03 — Decisões de arquitetura](docs/03-decisoes-de-arquitetura.md): o porquê de cada escolha
- [Histórico de mudanças](CHANGELOG.md): inclui os problemas que os testes encontraram durante a montagem

**Runbooks — como fazer**

| | |
|---|---|
| [RB-00](docs/runbooks/RB-00-subir-o-laboratorio.md) | Subir o laboratório do zero (Windows) |
| [RB-01](docs/runbooks/RB-01-controlador-de-dominio.md) | Controlador de domínio: montagem manual e verificação |
| [RB-02](docs/runbooks/RB-02-dns.md) | DNS: consultar, criar e remover registros |
| [RB-03](docs/runbooks/RB-03-dhcp.md) | DHCP: concessões, reservas, escopo |
| [RB-04](docs/runbooks/RB-04-usuarios-e-grupos.md) | Usuários: admissão, desligamento, senha, bloqueio, troca de setor |
| [RB-05](docs/runbooks/RB-05-servidor-de-arquivos.md) | Servidor de arquivos: nova pasta, permissões |
| [RB-06](docs/runbooks/RB-06-monitoramento.md) | Monitoramento: alertas, manutenção programada, novo alvo |
| [RB-07](docs/runbooks/RB-07-estacao-windows.md) | Estação Windows no domínio + RSAT |
| [RB-08](docs/runbooks/RB-08-backup-e-restauracao.md) | Backup e restauração |

**Problemas comuns — como resolver**

| | |
|---|---|
| [TS-01](docs/troubleshooting/TS-01-estacao-sem-ip.md) | Estação sem IP (169.254.x.x) |
| [TS-02](docs/troubleshooting/TS-02-nome-nao-resolve.md) | Nome não resolve / "domínio não disponível" |
| [TS-03](docs/troubleshooting/TS-03-usuario-nao-consegue-logar.md) | Usuário não consegue logar (senha, bloqueio, horário) |
| [TS-04](docs/troubleshooting/TS-04-acesso-negado-na-pasta.md) | Acesso negado na pasta compartilhada |
| [TS-05](docs/troubleshooting/TS-05-alerta-disparou.md) | Um alerta disparou — o que fazer em cada um |
| [TS-06](docs/troubleshooting/TS-06-vagrant-virtualbox-windows.md) | Vagrant/VirtualBox no Windows |

## Como sei que funciona

Nada aqui é "deveria funcionar": tudo é verificado por script, e os resultados reais estão em [`docs/evidencias/`](docs/evidencias/).

| Teste | O que prova | Resultado |
|---|---|---|
| [`smoke-test.sh`](tests/smoke-test.sh) | Do ponto de vista do usuário na ws01: DNS, DHCP real, ingresso no domínio, Kerberos, **quem grava, quem só lê e quem é barrado** em cada pasta, monitoramento sem alertas | [30/30](docs/evidencias/smoke-test.log) |
| [`dc-checks.sh`](tests/dc-checks.sh) | Integridade do banco do AD, política de senha, delegação do Helpdesk (pode resetar usuário, **não** pode resetar admin) | [10/10](docs/evidencias/dc-checks.log) |
| [`alert-drill.sh`](tests/alert-drill.sh) | Derruba o DHCP de propósito: alerta dispara em 35–45 s, chega ao Alertmanager e resolve ao religar | [ok](docs/evidencias/simulacao-alerta.log) |
| [`backup-drill.sh`](tests/backup-drill.sh) | Faz backup, apaga um usuário, restaura e confere se voltou com os mesmos grupos | [ok](docs/evidencias/teste-restauracao-backup.log) |
| [CI](.github/workflows/laboratorio.yml) | A cada mudança, o GitHub sobe o laboratório inteiro em contêineres e roda tudo acima | badge no topo |

Os mesmos scripts de `provision/` configuram as VMs e os contêineres de teste ([por que e quais as diferenças](docs/03-decisoes-de-arquitetura.md#d11--testes-automáticos-em-contêineres--ci)).

## Estrutura

```
├── Vagrantfile                 # as 4 VMs (VirtualBox)
├── provision/
│   ├── lab.env                 # TODOS os parâmetros: domínio, IPs, escopo, senhas do lab
│   ├── lib/common.sh           # passos comuns (rede, hora, métricas)
│   ├── dc01.sh fs01.sh mon01.sh ws01.sh   # um script idempotente por máquina
│   ├── data/                   # usuários, grupos e pastas em CSV
│   └── files/                  # templates (Kea, Samba, Prometheus...) e comandos de apoio
├── tests/                      # teste de fumaça, verificações, simulações, coletor de evidências
│   └── container-lab/          # o laboratório em contêineres (testes e CI)
└── docs/                       # inventário, diagrama, decisões, runbooks, troubleshooting, evidências
```

## Competências praticadas

Active Directory (OUs, grupos, política de senha, delegação de permissões) · DNS (zonas direta e reversa, registros SRV) · DHCP (escopo, opções, reservas) · Kerberos · permissões de arquivos por grupo (ACL) · Linux (systemd, netplan, Samba) · monitoramento e alertas · backup e teste de restauração · infraestrutura como código · troubleshooting metódico · documentação técnica.

## Próximos passos

- [ ] Segundo controlador de domínio (dc02) para tirar o ponto único de falha
- [ ] Gateway/firewall (OPNsense) em 10.10.10.1 e separação em VLANs (servidores x estações)
- [ ] Backup fora da máquina (regra 3-2-1)
- [ ] Painel no Grafana e alertas por e-mail/Telegram
- [ ] GPOs de exemplo (bloqueio de tela, unidade mapeada) aplicadas à estação Windows

## Aviso

As senhas em [`provision/lab.env`](provision/lab.env) são de **laboratório** e públicas de propósito, para qualquer pessoa reproduzir. Em produção, senha não vai para o Git.

---

Bernardo Paiva — projeto final da trilha de suporte e infraestrutura.

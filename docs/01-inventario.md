# 01 — Inventário do ambiente CORP.LAB

> **Fonte da verdade:** os valores desta página saem de [`provision/lab.env`](../provision/lab.env) e dos arquivos em [`provision/data/`](../provision/data/).
> Mudou um deles? Atualize esta página no mesmo commit.
> Para conferir se o inventário ainda bate com a realidade, rode `bash tests/coletar-evidencias.sh` e compare com [`evidencias/`](evidencias/).

| Item | Valor |
|---|---|
| Ambiente | Laboratório (homelab), imitando a TI de uma pequena empresa |
| Responsável | Bernardo Paiva |
| Última revisão | 26/10/2026 |
| Domínio AD / DNS | `corp.lab` |
| Realm Kerberos | `CORP.LAB` |
| Nome NetBIOS | `CORP` |
| Rede corporativa | `10.10.10.0/24` (rede interna do VirtualBox `corp-lan`) |

---

## 1. Servidores e estações

| Host | FQDN | IP | Função | Serviços críticos | SO | vCPU / RAM | MAC (placa 2) |
|---|---|---|---|---|---|---|---|
| **dc01** | dc01.corp.lab | 10.10.10.10 (fixo) | Controlador de domínio, DNS, DHCP, NTP | `samba-ad-dc`, `kea-dhcp4-server`, `chrony` | Ubuntu 24.04 LTS | 1 / 1024 MB | 08:00:27:AA:00:10 |
| **fs01** | fs01.corp.lab | 10.10.10.20 (fixo) | Servidor de arquivos (membro do domínio) | `smbd`, `winbind`, `chrony` | Ubuntu 24.04 LTS | 1 / 768 MB | 08:00:27:AA:00:20 |
| **mon01** | mon01.corp.lab | 10.10.10.30 (fixo) | Monitoramento e alertas | `prometheus`, `prometheus-alertmanager`, `prometheus-blackbox-exporter`, `chrony` | Ubuntu 24.04 LTS | 1 / 1024 MB | 08:00:27:AA:00:30 |
| **ws01** | ws01.corp.lab | DHCP (10.10.10.100–199) | Estação de funcionário, ponto de vista do usuário nos testes | `sssd`, `chrony` | Ubuntu 24.04 LTS | 1 / 768 MB | 08:00:27:AA:01:01 |

Todas as VMs têm **duas placas de rede**:

- **Placa 1 — NAT do VirtualBox** (`10.0.2.15`): acesso à internet para instalar pacotes e o `vagrant ssh`. Não faz parte da rede da empresa.
- **Placa 2 — Rede interna `corp-lan`**: a rede corporativa. O MAC é fixo (definido no `Vagrantfile`) para o script achar a placa certa e o DHCP reconhecer a máquina.

Total de recursos: **4 vCPU e ~3,5 GB de RAM** (recomendado: notebook com 8 GB ou mais).

## 2. Plano de endereçamento IP

Rede `10.10.10.0/24` (254 endereços úteis), dividida por faixas:

| Faixa | Uso |
|---|---|
| 10.10.10.1 | Reservado para um futuro gateway/firewall |
| 10.10.10.2 – 10.10.10.9 | Reservado (infraestrutura de rede) |
| 10.10.10.10 – 10.10.10.49 | **Servidores** (IP fixo, configurado na própria máquina) |
| 10.10.10.50 – 10.10.10.99 | **Reservas DHCP** (impressoras e equipamentos que precisam de IP previsível) |
| 10.10.10.100 – 10.10.10.199 | **Escopo DHCP** (estações) — concessão de 8 horas |
| 10.10.10.200 – 10.10.10.254 | Livre para expansão |

Reservas DHCP cadastradas:

| Equipamento | MAC | IP |
|---|---|---|
| impressora01 (exemplo) | 08:00:27:aa:00:50 | 10.10.10.50 |

## 3. DNS — zona `corp.lab` (integrada ao AD, no dc01)

| Nome | Tipo | Valor | Observação |
|---|---|---|---|
| dc01 | A | 10.10.10.10 | criado na promoção do DC |
| fs01 | A | 10.10.10.20 | |
| mon01 | A | 10.10.10.30 | |
| impressora01 | A | 10.10.10.50 | casa com a reserva DHCP |
| arquivos | CNAME | fs01.corp.lab | nome "amigável" para os usuários |
| monitor | CNAME | mon01.corp.lab | |
| _ldap._tcp, _kerberos._tcp … | SRV | dc01.corp.lab | criados automaticamente pelo AD; é por eles que os clientes acham o DC |

Zona reversa `10.10.10.in-addr.arpa`: PTR para .10 (dc01), .20 (fs01), .30 (mon01), .50 (impressora01). Estações registram o próprio nome sozinhas ao entrar no domínio.

Nomes da internet: o dc01 encaminha para `10.0.2.3` (DNS do NAT do VirtualBox).

## 4. Active Directory

### Unidades organizacionais (OUs)

```
corp.lab
└── CORP
    ├── Usuarios
    │   ├── TI
    │   ├── Financeiro
    │   ├── RH
    │   └── Comercial
    ├── Grupos
    ├── Servidores      (fs01)
    └── Estacoes        (ws01)
```

### Usuários

Origem: [`usuarios.csv`](../provision/data/usuarios.csv).

| Login | Nome | Departamento | Cargo | Grupos |
|---|---|---|---|---|
| ana.souza | Ana Souza | TI | Analista de Infraestrutura | GG_TI |
| rafael.nunes | Rafael Nunes | TI | Técnico de Suporte | GG_TI, **GG_Helpdesk** |
| bruno.lima | Bruno Lima | Financeiro | Coordenador Financeiro | GG_Financeiro, GG_Diretoria |
| carla.mendes | Carla Mendes | Financeiro | Analista Financeira | GG_Financeiro |
| diego.rocha | Diego Rocha | RH | Analista de RH | GG_RH |
| elisa.costa | Elisa Costa | Comercial | Gerente Comercial | GG_Comercial, GG_Diretoria |
| felipe.alves | Felipe Alves | Comercial | Vendedor | GG_Comercial |

### Grupos de segurança

Origem: [`grupos.csv`](../provision/data/grupos.csv).

| Grupo | Para que serve |
|---|---|
| GG_TI | Equipe de TI — escreve em `\\fs01\TI` |
| GG_Financeiro | Escreve em `\\fs01\Financeiro` |
| GG_RH | Escreve em `\\fs01\RH` |
| GG_Comercial | Escreve em `\\fs01\Comercial` |
| GG_Diretoria | **Só lê** Financeiro e Comercial |
| GG_Helpdesk | **Delegação:** redefine senha, desbloqueia conta e força troca de senha de usuários da OU `Usuarios` (não alcança administradores) |

### Política de senha e bloqueio

| Regra | Valor |
|---|---|
| Tamanho mínimo | 10 caracteres |
| Complexidade | ligada (maiúscula, minúscula, número/símbolo) |
| Validade | 90 dias |
| Histórico | não repete as 5 últimas |
| Bloqueio | após **5** senhas erradas, por **15 minutos** |

## 5. Compartilhamentos (fs01)

Origem: [`compartilhamentos.csv`](../provision/data/compartilhamentos.csv).

| Compartilhamento | Caminho no servidor | Leitura e escrita | Somente leitura | Sem acesso (nem enxerga) |
|---|---|---|---|---|
| `\\fs01\Publico` | /srv/compartilhamentos/Publico | Todos (Domain Users) | — | — |
| `\\fs01\TI` | /srv/compartilhamentos/TI | GG_TI | — | demais |
| `\\fs01\Financeiro` | /srv/compartilhamentos/Financeiro | GG_Financeiro | GG_Diretoria | demais |
| `\\fs01\RH` | /srv/compartilhamentos/RH | GG_RH | — | demais |
| `\\fs01\Comercial` | /srv/compartilhamentos/Comercial | GG_Comercial | GG_Diretoria | demais |

`Domain Admins` tem controle total em todos. "Nem enxerga" = *access based share enumeration*: a pasta nem aparece para quem não tem acesso.

## 6. Monitoramento (mon01)

| O que é vigiado | Como | Alerta |
|---|---|---|
| Máquina ligada e coletando métricas | node_exporter :9100 em dc01, fs01, mon01 | `MaquinaFora` |
| Responde ping | Blackbox ICMP por IP | `SemPing` |
| Kerberos 88, LDAP 389, SMB 445 (dc01) e SMB 445 (fs01) | Blackbox TCP | `PortaDeServicoFechada` |
| DNS responde o registro SRV do AD | Blackbox DNS (`_ldap._tcp.corp.lab`) | `DnsDoDominioFalhando` |
| Serviços críticos de cada máquina rodando | coletor systemd do node_exporter | `ServicoParado` |
| Disco com menos de 15% livre | node_exporter | `DiscoQuaseCheio` |
| Memória acima de 90% por 10 min | node_exporter | `MemoriaAlta` |

Acesso: <http://localhost:9090> (Prometheus) e <http://localhost:9093> (Alertmanager) a partir do notebook host. Detalhes: [RB-06](runbooks/RB-06-monitoramento.md).

## 7. Portas em uso

| Host | Porta | Serviço |
|---|---|---|
| dc01 | 53 TCP/UDP | DNS |
| dc01 | 67 UDP | DHCP |
| dc01 | 88 TCP/UDP | Kerberos |
| dc01 | 123 UDP | NTP |
| dc01 | 135, 49152+ TCP | RPC (gerenciamento do AD pelo Windows/RSAT) |
| dc01 | 389 TCP/UDP, 636 TCP | LDAP, LDAPS |
| dc01 | 445 TCP | SMB (SYSVOL, NETLOGON) |
| dc01 | 464 TCP/UDP | Troca de senha Kerberos |
| dc01 | 3268–3269 TCP | Catálogo global |
| fs01 | 445 TCP | SMB (compartilhamentos) |
| todos | 9100 TCP | node_exporter |
| mon01 | 9090 / 9093 / 9115 TCP | Prometheus / Alertmanager / Blackbox |

## 8. Contas e credenciais

| Conta | Onde | Senha |
|---|---|---|
| `CORP\Administrator` | Domínio | `LAB_ADMIN_PASSWORD` em [`lab.env`](../provision/lab.env) |
| Usuários do domínio | Domínio | `LAB_USER_PASSWORD` em [`lab.env`](../provision/lab.env) |
| `vagrant` | Todas as VMs (local) | acesso por chave, via `vagrant ssh` |

> ⚠️ As senhas do laboratório são **públicas de propósito**, para qualquer pessoa reproduzir o ambiente. Num ambiente real, senha nunca vai para o Git: ficaria num cofre de senhas (Bitwarden, KeePass, Vault) e o `lab.env` só teria a referência.

## 9. Rotinas automáticas

| Rotina | Onde | Quando | Detalhe |
|---|---|---|---|
| Backup a frio do AD + DHCP | dc01 (`backup-dc.timer`) | todo dia, 02:30 | `/var/backups/dc01`, guarda 7 cópias com sha256 — [RB-08](runbooks/RB-08-backup-e-restauracao.md) |
| Limpeza do arquivo de leases | dc01 (Kea LFC) | a cada 1 h | automático do Kea |
| Coleta de métricas | mon01 | a cada 15 s | retenção de 15 dias |

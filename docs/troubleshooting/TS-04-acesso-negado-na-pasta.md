# TS-04 — Acesso negado na pasta compartilhada

**Sintoma.** "Você não tem permissão para acessar \\\\fs01\\..." / `NT_STATUS_ACCESS_DENIED`; a pasta não aparece na lista; ou abre mas não deixa salvar.

## Primeiro: o acesso **deveria** existir?

Confira no [inventário](../01-inventario.md#5-compartilhamentos-fs01) quem tem direito. Se a pessoa não está no grupo certo, **não é defeito, é pedido de acesso**: precisa de autorização do dono da área (ex.: gestor do Financeiro) e depois [RB-04](../runbooks/RB-04-usuarios-e-grupos.md) para incluir no grupo.

## Diagnóstico

| # | Verifique | Comando | Esperado |
|---|---|---|---|
| 1 | Grupos da pessoa no AD | dc01: `samba-tool user getgroups <login> -U Administrator` | o grupo da pasta |
| 2 | Grupos que o **fs01** enxerga | fs01: `id <login>` | o mesmo grupo (minúsculo, ex.: `gg_financeiro`) |
| 3 | Quem pode conectar no compartilhamento | fs01: `testparm -s --section-name=<Pasta> 2>/dev/null` | o grupo em `valid users` |
| 4 | O que cada grupo pode fazer na pasta | fs01: `getfacl -p /srv/compartilhamentos/<Pasta>` | `group:gg_x:rwx` (grava) ou `r-x` (lê) |
| 5 | O que o servidor registrou | fs01: `tail -30 /var/log/samba/log.<IP-da-estação>` | o motivo da recusa |

## Causas comuns e correção

| Causa | Como reconhecer | Correção |
|---|---|---|
| Acabou de entrar no grupo e ainda não refez login | passo 1 ok; `whoami /groups` na estação **não** mostra o grupo | Logoff/logon (o grupo vai no ticket Kerberos emitido no login). No Linux: `kdestroy` e `kinit` de novo |
| Não está no grupo | passo 1 sem o grupo | Pedido de acesso (ver acima) |
| fs01 perdeu a ligação com o domínio | passo 2 falha (`no such user`); `wbinfo -t` falha | `systemctl restart winbind`; se `net ads testjoin` falhar, `net ads join -U Administrator` |
| Acesso pelo IP (`\\10.10.10.20`) | funciona pelo nome, falha pelo IP | Use `\\fs01.corp.lab` (por IP o Windows não usa Kerberos) |
| Arquivo criado sem herdar permissão | a pasta tem ACL certa, um arquivo específico não | `setfacl -m g:<grupo>:rwx <arquivo>`; confira se a pasta tem a ACL **padrão** (`default:`) — [RB-05 §2](../runbooks/RB-05-servidor-de-arquivos.md#2-criar-um-compartilhamento-novo) |
| Regra no compartilhamento vencendo a ACL | `testparm` mostra `read list`, `write list` ou `invalid users` | Ver o caso real abaixo |

## Caso real: o coordenador que não conseguia gravar

Encontrado pelos testes automáticos durante a montagem deste laboratório.

- **Sintoma:** `bruno.lima`, coordenador do Financeiro, abria `\\fs01\Financeiro`, lia os arquivos, mas ao salvar recebia `NT_STATUS_ACCESS_DENIED`. A analista `carla.mendes`, do mesmo setor, gravava normalmente.
- **Diagnóstico:** passo 1 mostrou que o Bruno está em **dois** grupos: `GG_Financeiro` (escrita) e `GG_Diretoria` (leitura em Financeiro e Comercial). Passo 3 mostrou `read list = @GG_Diretoria` no compartilhamento.
- **Causa:** no Samba, estar na `read list` deixa a conexão **inteira** somente leitura, não importa que outro grupo dê escrita. Mesma lógica do "Negar" no NTFS: a regra restritiva vence.
- **Correção:** tirar a `read list` do compartilhamento e controlar leitura/escrita **só pela ACL da pasta** (`g:gg_diretoria:r-x`, `g:gg_financeiro:rwx`). Na ACL as permissões dos grupos **se somam**, então o Bruno recebe escrita e a Elisa (só Diretoria) continua só lendo.
- **Prevenção:** decisão registrada em [D8](../03-decisoes-de-arquitetura.md#d8--permissões-nas-acls-da-pasta-não-em-regras-do-compartilhamento) e coberta pelo teste de fumaça (`Financeiro: bruno.lima grava` e `Financeiro: elisa.costa NÃO grava`).

## Como confirmar

Peça para a pessoa abrir e salvar um arquivo de teste. Na ws01: `sudo /opt/homelab/tests/smoke-test.sh`, seção **4**.

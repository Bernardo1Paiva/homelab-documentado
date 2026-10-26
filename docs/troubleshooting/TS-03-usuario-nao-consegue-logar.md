# TS-03 — Usuário não consegue fazer login

**Sintoma.** "Nome de usuário ou senha incorretos", "Sua conta foi bloqueada", "Sua conta foi desabilitada", "Sua senha expirou" ou erro de horário.

## Primeiro: ler a mensagem certa

O log de auditoria do dc01 diz exatamente **por que** o login foi recusado e **de onde** veio:

```bash
# no dc01
grep -i "<login>" /var/log/samba/log.samba | grep "status \[" | tail -5
```

| Status no log | Significa | Vá para |
|---|---|---|
| `NT_STATUS_WRONG_PASSWORD` | Senha errada | [Senha errada](#senha-errada-ou-esquecida) |
| `NT_STATUS_ACCOUNT_LOCKED_OUT` | Bloqueada por tentativas | [Conta bloqueada](#conta-bloqueada) |
| `NT_STATUS_ACCOUNT_DISABLED` | Desativada | [Conta desativada](#conta-desativada) |
| `NT_STATUS_PASSWORD_EXPIRED` / `NT_STATUS_PASSWORD_MUST_CHANGE` | Senha venceu (90 dias) ou troca obrigatória | [Senha expirada](#senha-expirada-ou-troca-obrigatória) |
| `NT_STATUS_NO_SUCH_USER` | Login digitado errado / conta não existe | confira com `samba-tool user list` |
| *(nada no log)* | O pedido nem chegou ao DC | [Nada chega ao DC](#nada-chega-ao-dc) |

Ficha da conta, para conferir tudo de uma vez:

```bash
samba-tool user show <login> --attributes=userAccountControl,lockoutTime,badPwdCount,pwdLastSet,accountExpires -U Administrator
```

## Senha errada ou esquecida

Confirme a identidade da pessoa e redefina com troca obrigatória — [RB-04 §3](../runbooks/RB-04-usuarios-e-grupos.md#3-esqueci-minha-senha-helpdesk). Lembre: Caps Lock e teclado em outro idioma (ABNT2 x US) são campeões de chamado.

## Conta bloqueada

5 senhas erradas → bloqueio de 15 min. **Antes de desbloquear, ache a origem**: o campo `remote host` do log mostra o IP. Se não é o computador da pessoa, é algo com senha antiga salva (celular no Wi-Fi, unidade mapeada, outro PC). Corrija lá, senão volta a bloquear.

```bash
samba-tool user unlock <login> -H ldap://dc01.corp.lab -U rafael.nunes   # Helpdesk pode
```

Testado no laboratório: 6 tentativas erradas no `felipe.alves` → bloqueio; desbloqueio pelo `rafael.nunes` (GG_Helpdesk) funcionou; tentativa pelo `diego.rocha` foi recusada com `LDAP_INSUFFICIENT_ACCESS_RIGHTS`.

## Conta desativada

`userAccountControl` com o bit 2 (ex.: `514`, `66050`). Normalmente é desligamento ([RB-04 §2](../runbooks/RB-04-usuarios-e-grupos.md#2-desligamento-funcionário-saiu)). **Só reative com pedido formal** do gestor/RH: `samba-tool user enable <login> -U Administrator`.

## Senha expirada ou troca obrigatória

`pwdLastSet: 0` = troca obrigatória no próximo login. No Windows a própria tela de login pede a nova senha. A senha nova precisa ter **10+ caracteres, complexa e diferente das 5 últimas** — se a pessoa diz que "não aceita", geralmente é isso.

## Nada chega ao DC

| Verifique | Comando | Correção |
|---|---|---|
| Estação acha o DC pelo DNS | `nslookup -type=SRV _ldap._tcp.corp.lab` | [TS-02](TS-02-nome-nao-resolve.md) |
| Relógio da estação x DC (Kerberos tolera **5 min**) | Win: `w32tm /stripchart /computer:dc01.corp.lab /samples:3` · Linux: `chronyc tracking` · dc01: `date` | Win: `w32tm /resync` · Linux: `systemctl restart chrony` · no dc01: `chronyc sources` |
| Estação ainda é membro do domínio | Win: `Test-ComputerSecureChannel` · Linux: `sudo adcli testjoin` | Win: `Test-ComputerSecureChannel -Repair -Credential CORP\Administrator` · Linux: no host, `vagrant provision ws01` (refaz o ingresso com `adcli join`) |
| SSSD (Linux) com cache velho | `id <login>` não mostra os grupos novos | `sss_cache -E && systemctl restart sssd` |

## Como confirmar

Pessoa loga. Na ws01, o equivalente é: `kinit <login>` sem erro e `klist` mostrando o ticket.

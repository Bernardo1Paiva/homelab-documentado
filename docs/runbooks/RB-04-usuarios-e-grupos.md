# RB-04 — Usuários e grupos (admissão, desligamento e suporte do dia a dia)

| | |
|---|---|
| **Objetivo** | Os procedimentos de conta mais pedidos ao suporte |
| **Onde** | dc01 (`vagrant ssh dc01` → `sudo -i`) ou **Usuários e Computadores do AD** (RSAT) no Windows |
| **Automação** | usuários iniciais vêm de [`usuarios.csv`](../../provision/data/usuarios.csv) e [`grupos.csv`](../../provision/data/grupos.csv) |
| **Quem pode** | Administrador: tudo. **GG_Helpdesk** (rafael.nunes): redefinir senha, desbloquear e forçar troca — só na OU `Usuarios` |

Nos comandos abaixo, `-U Administrator` pede a senha. Rodando de outra máquina, acrescente `-H ldap://dc01.corp.lab`.

**Regra da casa:** permissão se dá por **grupo**, nunca direto para a pessoa. O usuário entra no grupo do departamento e herda os acessos.

---

## 1. Admissão (funcionário novo)

Exemplo: Gabriel Teixeira, Comercial, Vendedor.

```bash
samba-tool user create gabriel.teixeira 'SenhaInicial@2026' \
  --given-name=Gabriel --surname=Teixeira \
  --department=Comercial --job-title=Vendedor \
  --mail-address=gabriel.teixeira@corp.lab \
  --userou="OU=Comercial,OU=Usuarios,OU=CORP" \
  --must-change-at-next-login \
  -U Administrator

samba-tool group addmembers GG_Comercial gabriel.teixeira -U Administrator
samba-tool user getgroups gabriel.teixeira -U Administrator      # confere: Domain Users, GG_Comercial
```

- Padrão de login: `nome.sobrenome`, minúsculo, sem acento.
- Senha inicial entregue por canal separado (pessoalmente/telefone), nunca no mesmo e-mail do login.
- `--must-change-at-next-login` obriga a pessoa a criar a própria senha.
- Para ficar permanente no laboratório, acrescente a linha no `usuarios.csv`.

## 2. Desligamento (funcionário saiu)

**Desative, não apague.** Apagar perde o histórico e os arquivos ficam com "dono desconhecido".

```bash
samba-tool user disable gabriel.teixeira -U Administrator
samba-tool user getgroups gabriel.teixeira -U Administrator      # anote os grupos (para o chamado)
samba-tool group removemembers GG_Comercial gabriel.teixeira -U Administrator
samba-tool user setpassword gabriel.teixeira --random-password -U Administrator
```

Registre no chamado: data, quem pediu, grupos removidos. Exclusão definitiva só depois do prazo da política da empresa (ex.: 90 dias): `samba-tool user delete gabriel.teixeira -U Administrator`.

## 3. Esqueci minha senha (Helpdesk)

Confirme a identidade da pessoa antes. Depois, o técnico do Helpdesk faz **com a própria conta**:

```bash
samba-tool user setpassword felipe.alves --newpassword='Temporaria@2026' \
  --must-change-at-next-login -H ldap://dc01.corp.lab -U rafael.nunes
```

Se quem tentar não estiver no GG_Helpdesk, recebe `LDAP_INSUFFICIENT_ACCESS_RIGHTS` — é a delegação funcionando. Ela também **não** alcança contas fora da OU `Usuarios` (ex.: Administrator), o que foi testado em [`dc-checks.sh`](../../tests/dc-checks.sh).

## 4. Conta bloqueada

Após **5 senhas erradas** a conta trava por **15 minutos**. Na tela aparece "conta bloqueada"; no Linux, `kinit` diz *Client's credentials have been revoked*.

```bash
# quem está bloqueado agora?
ldbsearch -H ldap://127.0.0.1 -U Administrator -b "OU=Usuarios,OU=CORP,DC=corp,DC=lab" \
  "(&(objectClass=user)(lockoutTime>=1))" sAMAccountName badPwdCount

# desbloquear (Helpdesk pode)
samba-tool user unlock felipe.alves -H ldap://dc01.corp.lab -U rafael.nunes
```

**Antes de desbloquear, descubra de onde vieram as tentativas** — senão a conta trava de novo em minutos (celular com senha antiga no Wi-Fi, unidade de rede mapeada com senha salva):

```bash
grep -i "felipe.alves" /var/log/samba/log.samba | grep -E "WRONG_PASSWORD|LOCKED_OUT" | tail -5
```

O campo `remote host` mostra o IP de origem. Mais em [TS-03](../troubleshooting/TS-03-usuario-nao-consegue-logar.md).

## 5. Mudou de setor

```bash
samba-tool group removemembers GG_Comercial felipe.alves -U Administrator
samba-tool group addmembers GG_Financeiro felipe.alves -U Administrator
samba-tool user move felipe.alves "OU=Financeiro,OU=Usuarios,OU=CORP" -U Administrator
```

A pessoa precisa **sair e entrar de novo** (logoff/logon) para o novo grupo valer: os grupos vão dentro do ticket Kerberos, emitido no login.

## 6. Consultas úteis

```bash
samba-tool user list -U Administrator                                   # todos os logins
samba-tool user show felipe.alves -U Administrator                      # ficha completa
samba-tool group listmembers GG_Financeiro -U Administrator             # quem está no grupo
samba-tool user getgroups felipe.alves -U Administrator                 # grupos da pessoa
samba-tool user setexpiry estagiario.x --days=90 -U Administrator       # conta com data para expirar
samba-tool domain passwordsettings show -U Administrator                # política de senha
```

## 7. Criar um grupo novo

```bash
samba-tool group add GG_Juridico --groupou="OU=Grupos,OU=CORP" \
  --description="Departamento Jurídico" -U Administrator
```

Nome sempre com prefixo `GG_` (grupo global). Atualize o [inventário](../01-inventario.md#grupos-de-segurança) e o `grupos.csv`.

## Como confirmar

Da ws01: `id <login>` mostra os grupos; `kinit <login>` com a senha nova funciona.

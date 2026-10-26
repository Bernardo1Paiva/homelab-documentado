# RB-07 — Colocar uma estação Windows no domínio

| | |
|---|---|
| **Objetivo** | Uma VM Windows na rede `corp-lan`, no domínio CORP.LAB, com login de usuário do AD e gerenciamento pelo RSAT |
| **Onde** | VirtualBox no host + a própria VM Windows |
| **Tempo** | ~40 min (a maior parte é a instalação do Windows) |
| **Automação** | Manual — não faz parte do `vagrant up` nem dos testes automáticos (a imagem do Windows é grande e tem licença de avaliação) |

## Pré-requisitos

- O laboratório no ar (`vagrant status`: dc01 rodando).
- ISO do **Windows 11 Enterprise — avaliação** (90 dias, gratuita) do Microsoft Evaluation Center. **Edição Home não entra em domínio**; use Pro, Enterprise ou Education.
- 4 GB de RAM livres e ~40 GB de disco.

## 1. Criar a VM no VirtualBox

1. **Nova** → nome `ws02-win`, ISO do Windows, marque **"Pular instalação desassistida"** (para escolher a edição).
2. Memória 4096 MB, 2 CPUs, disco 40 GB.
3. **Configurações → Rede → Adaptador 1**: *Conectado a* = **Rede Interna**, *Nome* = **`corp-lan`** (digite exatamente). É assim que ela entra na rede da empresa.
4. Instale o Windows normalmente, com uma conta local (ex.: `suporte`).

> Sem o adaptador NAT, essa VM não tem internet — igual a uma estação numa rede corporativa sem rota para fora. Para ter internet (Windows Update), adicione um **Adaptador 2** em **NAT**.

## 2. Conferir rede e DNS

No **Prompt de Comando**:

```bat
ipconfig /all
```

Esperado no adaptador da `corp-lan`: IP entre **10.10.10.100 e .199**, *Servidores DNS* = **10.10.10.10**, *Sufixo DNS* = **corp.lab**.

```bat
nslookup -type=SRV _ldap._tcp.corp.lab
ping dc01.corp.lab
```

Se não pegou IP: [TS-01](../troubleshooting/TS-01-estacao-sem-ip.md). Se o `nslookup` falhar: [TS-02](../troubleshooting/TS-02-nome-nao-resolve.md).

## 3. Ingressar no domínio

No **PowerShell como Administrador**:

```powershell
Add-Computer -DomainName corp.lab `
  -OUPath "OU=Estacoes,OU=CORP,DC=corp,DC=lab" `
  -Credential CORP\Administrator -Restart
```

(Pela interface: `sysdm.cpl` → **Alterar** → **Domínio**: `corp.lab`.)

## 4. Entrar com um usuário do domínio

Na tela de login: **Outro usuário** → `CORP\ana.souza` (ou `ana.souza@corp.lab`) com a senha do laboratório.

Teste as pastas:

```bat
net use P: \\fs01.corp.lab\Publico /persistent:yes
net use T: \\fs01.corp.lab\TI /persistent:yes
dir \\fs01.corp.lab\Financeiro
```

Esperado para a `ana.souza` (GG_TI): P: e T: funcionam; Financeiro dá **acesso negado** — e nem aparece em `\\fs01.corp.lab`.

```bat
whoami /groups | findstr GG_
klist
```

`klist` mostra os tickets Kerberos (incluindo `cifs/fs01.corp.lab`) — prova de que o acesso às pastas usou Kerberos, não senha.

## 5. Gerenciar o AD pelo Windows (RSAT)

Logado com uma conta de **Domain Admins** (`CORP\Administrator`), PowerShell como Administrador:

```powershell
Get-WindowsCapability -Online -Name "Rsat.ActiveDirectory*", "Rsat.Dns*", "Rsat.GroupPolicy*" |
  Add-WindowsCapability -Online
```

Ferramentas que aparecem em **Ferramentas do Windows**:

| Ferramenta | Use para |
|---|---|
| Usuários e Computadores do Active Directory (`dsa.msc`) | Contas, grupos, OUs, redefinir senha, desbloquear |
| DNS (`dnsmgmt.msc`) → conectar a `dc01.corp.lab` | Registros e zonas |
| Gerenciamento de Política de Grupo (`gpmc.msc`) | GPOs (ex.: papel de parede, mapear unidade, política de bloqueio de tela) |

Tudo o que se faz nelas vale igual ao `samba-tool` do [RB-04](RB-04-usuarios-e-grupos.md): é o mesmo AD.

## Como confirmar

- `Get-ADComputer ws02-win` (com RSAT) ou, no dc01: `samba-tool computer list -U Administrator` mostra `WS02-WIN$`.
- No dc01: `grep ana.souza /var/log/samba/log.samba | tail -3` mostra o login vindo do IP da ws02-win.

## Se der errado

| Mensagem | Causa provável | Solução |
|---|---|---|
| "Não foi possível contatar um controlador de domínio" | DNS da VM não é o 10.10.10.10 | [TS-02](../troubleshooting/TS-02-nome-nao-resolve.md) |
| "A relação de confiança entre esta estação e o domínio falhou" | Senha da conta de computador dessincronizada (ex.: restaurou snapshot antigo da VM) | Logue com a conta local e: `Test-ComputerSecureChannel -Repair -Credential CORP\Administrator` |
| Opção "Domínio" acinzentada | Windows Home | Use Pro/Enterprise |
| Login demora e falha com "horário" | Relógio da VM diferente do dc01 | `w32tm /resync`, ou acerte a hora — [TS-03](../troubleshooting/TS-03-usuario-nao-consegue-logar.md) |

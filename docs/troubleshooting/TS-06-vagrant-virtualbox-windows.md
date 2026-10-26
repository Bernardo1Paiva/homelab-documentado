# TS-06 — Problemas do Vagrant e VirtualBox no Windows

Problemas na **sua máquina**, antes de o laboratório em si funcionar.

## "VT-x is not available" / "AMD-V is disabled in the BIOS"

A virtualização está desligada no processador. Entre na BIOS/UEFI (tecla Del, F2 ou F10 ao ligar), procure **Intel Virtualization Technology (VT-x)** ou **SVM Mode (AMD)**, habilite e salve. Confira depois no Gerenciador de Tarefas → Desempenho → CPU → "Virtualização: Habilitado".

## VM muito lenta (tartaruga verde)

O ícone de tartaruga verde no canto da janela da VM significa que o VirtualBox está rodando **por cima do Hyper-V** do Windows (que fica ativo com WSL2, Docker Desktop, Sandbox ou "Plataforma de Máquina Virtual"). Funciona, mas lento — o provisionamento pode passar de uma hora.

Para desativar o hypervisor do Windows (PowerShell como Administrador, depois **reinicie**):

```powershell
bcdedit /set hypervisorlaunchtype off
```

Para voltar a usar WSL2/Docker Desktop depois: `bcdedit /set hypervisorlaunchtype auto` e reinicie.

## "The box 'bento/ubuntu-24.04' could not be found"

O Vagrant não conseguiu falar com o catálogo de imagens (HashiCorp Cloud). Já aconteceu por instabilidade do serviço (erro HTTP 502). Verifique a internet/proxy e tente de novo mais tarde. Para conferir: `vagrant box add bento/ubuntu-24.04 --provider virtualbox`.

## Script falha com `$'\r': command not found`

O Git do Windows converteu os scripts para fim de linha do Windows (CRLF). O `.gitattributes` do projeto e o próprio `Vagrantfile` já protegem contra isso; se ainda acontecer (ex.: arquivo editado no Bloco de Notas antigo), reconverta e reprovisione.

> ⚠️ O `git reset --hard` abaixo **descarta alterações não commitadas** na pasta do projeto. Faça commit (ou copie) antes.

```bash
git config core.autocrlf false
git rm --cached -r . -q && git reset --hard
vagrant provision <vm>
```

## "Vagrant cannot forward the specified ports... port 9090 already in use"

Outro programa já usa a porta 9090 no Windows. Descubra qual: `netstat -ano | findstr :9090` (a última coluna é o PID; veja no Gerenciador de Tarefas). Feche o programa, ou troque a porta do host no `Vagrantfile` (`9090 => 19090`) e acesse `localhost:19090`.

## `vagrant up` travado em "SSH auth method: private key"

Normal por 1–2 minutos na primeira subida (a VM está dando boot). Passou de 5 minutos: abra a janela da VM no VirtualBox para ver o que aparece na tela; antivírus/firewall bloqueando a porta 2222 local é um suspeito comum.

## Erro de provisionamento no meio do `vagrant up`

As outras VMs não sobem se uma falhar. Leia a última linha vermelha `ERRO:` (os scripts dizem o que esperavam). Corrija e continue de onde parou:

```bash
vagrant provision <vm-que-falhou>
vagrant up                      # sobe as que faltam
```

Os scripts são idempotentes: rodar de novo não duplica usuário, compartilhamento nem registro DNS.

## Pouca memória no notebook

Com 8 GB é apertado mas funciona. Feche o navegador durante o `vagrant up`. Se preciso, reduza no `Vagrantfile` (`memory: 768` no mon01; o dc01 não deve ficar abaixo de 1024) e trabalhe com menos VMs ligadas (`vagrant halt ws01` quando não estiver testando).

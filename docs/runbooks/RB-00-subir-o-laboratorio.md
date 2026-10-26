# RB-00 — Subir o laboratório do zero (Windows)

| | |
|---|---|
| **Objetivo** | Ter as 4 VMs (dc01, fs01, mon01, ws01) rodando e testadas |
| **Onde** | Notebook/PC com Windows 10 ou 11 (64 bits) |
| **Tempo** | ~15 min de instalação + ~20 min do `vagrant up` na primeira vez |
| **Risco** | Baixo — tudo fica isolado numa rede interna do VirtualBox |

## Pré-requisitos

| Requisito | Mínimo | Como conferir |
|---|---|---|
| Memória RAM | 8 GB (as VMs usam ~3,5 GB) | Gerenciador de Tarefas → Desempenho → Memória |
| Disco livre | 20 GB | Explorador de Arquivos → Este Computador |
| Virtualização na CPU | Habilitada | Gerenciador de Tarefas → Desempenho → CPU → "Virtualização: **Habilitado**". Se aparecer "Desabilitado", ligue **Intel VT-x / AMD-V (SVM)** na BIOS/UEFI |
| Internet | Sim | Para baixar a imagem do Ubuntu (~1 GB) e os pacotes |

## 1. Instalar as ferramentas

Abra o **PowerShell como Administrador** e rode:

```powershell
winget install --id Oracle.VirtualBox -e
winget install --id Hashicorp.Vagrant -e
winget install --id Git.Git -e
```

Versões testadas: **VirtualBox 7.2** e **Vagrant 2.4.9** ou mais novo. **Reinicie o computador** depois de instalar o Vagrant (ele altera o PATH).

> **Hyper-V / WSL2 / Docker Desktop instalados?** O VirtualBox 7 funciona junto com o Hyper-V, mas bem mais lento (aparece uma tartaruga verde no canto da VM). Se ficar lento demais, veja [TS-06](../troubleshooting/TS-06-vagrant-virtualbox-windows.md#vm-muito-lenta-tartaruga-verde).

## 2. Baixar o projeto

No **Git Bash** (ou PowerShell comum):

```bash
cd ~/Documents
git clone https://github.com/Bernardo1Paiva/homelab-documentado.git
cd homelab-documentado
```

O arquivo `.gitattributes` garante que os scripts mantenham o fim de linha do Linux mesmo clonados no Windows. (O `Vagrantfile` também corrige isso dentro das VMs, por garantia.)

## 3. Subir as máquinas

```bash
vagrant up
```

O Vagrant sobe uma VM por vez, **nesta ordem**: `dc01` → `fs01` → `mon01` → `ws01` (os outros dependem do controlador de domínio). Cada script imprime o que está fazendo e termina com uma linha verde `OK: ... pronto`.

Para acompanhar no VirtualBox: as VMs ficam no grupo **homelab-corp-lab**.

Se algo falhar no meio, corrija e rode só a máquina afetada:

```bash
vagrant provision fs01      # roda o script de novo (é seguro: ele não duplica nada)
```

## 4. Validar

```bash
vagrant status                                                   # as 4 devem estar "running"
vagrant ssh ws01 -c "sudo /opt/homelab/tests/smoke-test.sh"      # 30 verificações do ponto de vista do usuário
vagrant ssh dc01 -c "sudo /opt/homelab/tests/dc-checks.sh"       # saúde do AD e delegação do Helpdesk
```

Resultado esperado: `Resultado: 30 passaram, 0 falharam` e `Resultado: 10 passaram, 0 falharam`. Exemplo real: [evidencias/smoke-test.log](../evidencias/smoke-test.log).

No navegador do Windows:

- <http://localhost:9090/targets> — todos os alvos **UP**
- <http://localhost:9093> — Alertmanager sem alertas

Testes de "incidente" (opcionais, rodam no Git Bash na pasta do projeto):

```bash
bash tests/alert-drill.sh        # derruba o DHCP e confere se o alerta dispara e se resolve
bash tests/backup-drill.sh       # apaga um usuário, restaura o backup e confere se voltou
bash tests/coletar-evidencias.sh # grava o estado real em docs/evidencias/
```

## 5. Dia a dia

| Quero… | Comando |
|---|---|
| Ver o estado das VMs | `vagrant status` |
| Entrar numa VM | `vagrant ssh dc01` (depois `sudo -i` para virar root) |
| Desligar tudo (mantém os dados) | `vagrant halt` |
| Ligar de novo | `vagrant up` (não reprovisiona, só liga) |
| Reaplicar a configuração de uma VM | `vagrant provision fs01` |
| Apagar tudo e começar do zero | `vagrant destroy -f` e depois `vagrant up` |

> Ao ligar de novo, suba o **dc01 primeiro** (o `vagrant up` já respeita a ordem). Se ligar só a ws01, ela não terá DHCP nem login de domínio.

## Se der errado

| Sintoma | Vá para |
|---|---|
| Erro do Vagrant/VirtualBox antes da VM ligar | [TS-06](../troubleshooting/TS-06-vagrant-virtualbox-windows.md) |
| ws01 sem IP / `adcli info corp.lab` falha | [TS-01](../troubleshooting/TS-01-estacao-sem-ip.md) e [TS-02](../troubleshooting/TS-02-nome-nao-resolve.md) |
| Teste de pastas falhando | [TS-04](../troubleshooting/TS-04-acesso-negado-na-pasta.md) |

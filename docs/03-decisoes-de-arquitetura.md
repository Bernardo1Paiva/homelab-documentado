# 03 — Decisões de arquitetura

Registro do **porquê** de cada escolha. Quem assumir o ambiente não precisa adivinhar se algo foi pensado ou foi acaso — e, se o contexto mudar, sabe o que reavaliar.

Formato de cada decisão: **contexto → decisão → consequências**.

---

## D1 — Active Directory com Samba em Linux, não Windows Server

**Contexto.** O objetivo é um domínio AD reproduzível por qualquer pessoa, num notebook comum, com um comando. O Windows Server de avaliação expira em 180 dias, a ISO tem ~5 GB, pede 2 GB+ de RAM por VM e a instalação é difícil de automatizar de ponta a ponta.

**Decisão.** Samba 4 como controlador de domínio (Samba AD DC). Ele implementa o protocolo do Active Directory: Kerberos, LDAP, DNS integrado, GPO, e é gerenciado pelas mesmas ferramentas do Windows (RSAT: *Usuários e Computadores do AD*, *DNS*, *Gerenciamento de Política de Grupo*).

**Consequências.**
- ✅ Gratuito, leve (1 GB de RAM), 100% automatizado e testável.
- ✅ Uma estação Windows entra no domínio normalmente — ver [RB-07](runbooks/RB-07-estacao-windows.md).
- ⚠️ Alguns recursos do Windows Server não existem (AD CS/autoridade certificadora, DHCP gerenciado pelo console do Windows). O conceito (OU, grupo, GPO, Kerberos, SRV) é o mesmo — o conhecimento vale para os dois.

## D2 — Infraestrutura como código (Vagrant + scripts) em vez de VMs feitas na mão

**Contexto.** Laboratório montado clicando não se reproduz: ninguém lembra o que foi clicado.

**Decisão.** `Vagrantfile` descreve as VMs; um script por máquina em `provision/` faz toda a configuração; os dados (usuários, grupos, pastas) ficam em CSV.

**Consequências.**
- ✅ `vagrant destroy -f && vagrant up` recria tudo igual. O próprio código é documentação exata.
- ✅ Os scripts são **idempotentes**: rodar de novo (`vagrant provision`) não duplica nada.
- ⚠️ Cada runbook mostra também o **passo manual equivalente**, para entender o que o script faz e para quando for preciso fazer à mão num servidor que não é do laboratório.

## D3 — Nome do domínio `corp.lab`

**Contexto.** `.local` é usado pelo mDNS (Bonjour/Avahi) e causa falhas de resolução difíceis de diagnosticar. Domínio de um rótulo só (`CORP`) não é suportado direito.

**Decisão.** `corp.lab` para o laboratório.

**Consequências.** Em produção, o recomendado é um **subdomínio de um domínio registrado** da empresa (ex.: `ad.empresa.com.br`), que nunca vai colidir com nada na internet.

## D4 — Kea como servidor DHCP

**Contexto.** O `isc-dhcp-server`, clássico em tutoriais, chegou ao fim de vida em 2022. O sucessor do mesmo fabricante (ISC) é o Kea.

**Decisão.** Kea DHCPv4, configuração em JSON gerada de um template ([`kea-dhcp4.conf.tpl`](../provision/files/kea-dhcp4.conf.tpl)) e validada (`kea-dhcp4 -t`) antes de aplicar.

**Consequências.** Escopo, opções (DNS, domínio, NTP) e reservas ficam versionados no Git; configuração inválida nunca chega a derrubar o serviço.

## D5 — DHCP no mesmo servidor do AD

**Contexto.** Em empresa pequena com Windows é comum o DC acumular AD + DNS + DHCP.

**Decisão.** Manter no dc01, imitando esse cenário.

**Consequências.** Menos VMs; em compensação o dc01 vira ponto único de falha para três serviços (ver D7).

## D6 — Prometheus + Alertmanager + Blackbox para monitoramento

**Contexto.** Opções avaliadas: Zabbix (completo, mas pesado e configurado pela interface), Uptime Kuma (simples, mas configurado clicando), Prometheus (configurado por arquivo).

**Decisão.** Prometheus para coletar e avaliar regras, Blackbox Exporter para testar os serviços "de fora" (como o usuário vê), Alertmanager para agrupar e entregar alertas. Todos vêm do repositório oficial do Ubuntu.

**Consequências.**
- ✅ Alvos e regras ficam no Git, com validação (`promtool`, `amtool`) antes de aplicar.
- ✅ Cada alerta aponta para o runbook que resolve.
- ⚠️ Sem painel gráfico (Grafana): a visão é pela interface do Prometheus e pelos comandos `alvos` e `alertas`. Grafana é uma evolução natural.

## D7 — Um único controlador de domínio

**Contexto.** Recursos limitados num notebook.

**Decisão.** Aceitar o risco de um DC só, mitigado por **backup diário testado** ([RB-08](runbooks/RB-08-backup-e-restauracao.md)) e por **monitoramento** do serviço.

**Consequências.** Se o dc01 cair, a empresa fica sem login novo, DHCP e DNS (ver [leitura de impacto](02-diagrama-de-rede.md#leitura-de-impacto)). Em produção: no mínimo dois DCs.

## D8 — Permissões nas ACLs da pasta, não em regras do compartilhamento

**Contexto.** Nos testes automáticos, o `bruno.lima` (escrita no Financeiro pelo GG_Financeiro, e também da GG_Diretoria, só leitura) **não conseguia gravar**. Causa: a opção `read list` do Samba, aplicada ao GG_Diretoria, **vence** a permissão de escrita — o mesmo tipo de armadilha de "negar vence permitir" do NTFS.

**Decisão.** O compartilhamento só define **quem pode conectar** (`valid users`). **O que cada um pode fazer** fica na ACL da pasta, onde as permissões dos grupos **se somam** (como no NTFS sem "Negar").

**Consequências.** Quem está em dois grupos recebe a soma das permissões — o comportamento que o usuário espera. Caso documentado em [TS-04](troubleshooting/TS-04-acesso-negado-na-pasta.md).

## D9 — Mapeamento de IDs `rid` no servidor de arquivos

**Contexto.** Linux precisa de números (UID/GID) para usuários e grupos do AD.

**Decisão.** `idmap config CORP : backend = rid`: o número é calculado a partir do identificador do objeto no AD.

**Consequências.** O mesmo usuário tem o mesmo UID em qualquer servidor membro, sem cadastrar atributos Unix no AD. Se um dia houver um segundo servidor de arquivos, as permissões batem.

## D10 — Backup "a frio" do AD

**Contexto.** O `samba-tool domain backup` gera backups pensados para **criar um DC novo, com outro nome** (recuperação de desastre em outro servidor). Testado no laboratório: restaurar com o mesmo nome (dc01) falha por conflito com o objeto do próprio DC.

**Decisão.** Backup a frio: para o serviço por ~2 segundos, copia `/var/lib/samba`, `/etc/samba`, Kerberos e Kea preservando ACLs e atributos estendidos, religa. Restauração é o caminho inverso, com conferência de integridade (sha256).

**Consequências.** ✅ Restauração testada automaticamente (usuário apagado volta com os mesmos grupos). ⚠️ Serve para **um DC só**. Com dois ou mais DCs, nunca restaure um DC antigo por cima: a replicação resolve, e restaurar exige procedimento *autoritativo* específico.

## D11 — Testes automáticos em contêineres + CI

**Contexto.** Documentação que não é testada envelhece calada.

**Decisão.** Os **mesmos scripts** de `provision/` rodam em contêineres com systemd ([`tests/container-lab/`](../tests/container-lab/)), seguidos do teste de fumaça, da simulação de alerta e do teste de restauração. O GitHub Actions faz isso a cada mudança.

**Consequências.** Toda alteração é validada sem precisar subir as VMs. Diferenças conhecidas do contêiner em relação à VM: a rede é dada pelo Docker (sem netplan) e o relógio é o do host (sem chrony).

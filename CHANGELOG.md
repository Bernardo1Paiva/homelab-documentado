# Histórico de mudanças

Formato: data — o que mudou — por quê.

## v1.0 — 26/10/2026 — Primeira versão do ambiente

Ambiente completo: dc01 (AD, DNS, DHCP, NTP, backup), fs01 (arquivos), mon01 (monitoramento), ws01 (estação), com inventário, diagrama, decisões de arquitetura, 9 runbooks, 6 guias de problemas e testes automáticos.

### Problemas encontrados nos testes durante a montagem

Registrados porque são exatamente o tipo de coisa que acontece em produção — e porque mostram que a documentação foi validada, não só escrita.

| # | Problema | Como apareceu | Causa | Correção |
|---|---|---|---|---|
| 1 | Pastas compartilhadas não abriam (`NT_STATUS_BAD_NETWORK_NAME`) | Teste de fumaça, seção 4 | O módulo `acl_xattr` (permissões estilo Windows) fica no pacote `samba-vfs-modules`, que não é instalado quando se instala sem os pacotes "recomendados" | Pacote incluído no `fs01.sh` |
| 2 | Coordenador do Financeiro lia mas não gravava | Teste de fumaça: `bruno.lima grava` falhou | `read list` do compartilhamento vence a permissão de escrita de outro grupo | Permissões só na ACL da pasta — [TS-04](docs/troubleshooting/TS-04-acesso-negado-na-pasta.md#caso-real-o-coordenador-que-não-conseguia-gravar), [D8](docs/03-decisoes-de-arquitetura.md#d8--permissões-nas-acls-da-pasta-não-em-regras-do-compartilhamento) |
| 3 | Alarme falso `ServicoParado` para `samba-ad-dc` no fs01 | Teste: "nenhum alerta disparado" falhou | O monitoramento vigiava a mesma lista de serviços em todas as máquinas; no fs01 o serviço de DC existe instalado mas não deve rodar | Cada máquina declara seus próprios serviços críticos (`base_setup ... "smbd winbind"`) |
| 4 | Kea recusou a configuração | Provisionamento do dc01 | Chave `output-options` (com hífen) não existe no Kea 2.4: o certo é `output_options` | Template corrigido; a validação `kea-dhcp4 -t` antes de aplicar impediu que o serviço caísse |
| 5 | Restaurar o AD com `samba-tool domain backup restore` falhou | Teste de restauração | Essa ferramenta cria um DC **novo, com outro nome**; não serve para devolver o próprio dc01 | Backup a frio com `backup-dc` / `restaurar-dc` — [D10](docs/03-decisoes-de-arquitetura.md#d10--backup-a-frio-do-ad) |
| 6 | Alerta de disco "quase cheio" só no teste em contêiner | Teste de fumaça | O contêiner enxergava o disco do servidor de testes | Exclusão de pontos de montagem só no modo contêiner |
| 7 | Sonda de DHCP sem resposta só no contêiner | Teste de fumaça, seção 2 | `/tmp` montado sem permissão de execução no contêiner | `--tmpfs /tmp:exec` no harness |
| 8 | Provisionamento da ws01 travou no CI do GitHub | Primeira execução do GitHub Actions: parado na instalação de pacotes por mais de 20 min | O `realm join` depende do PackageKit e do polkit (feitos para desktop); a instalação do PackageKit ficou esperando um serviço que não sobe em ambiente sem interface | Ingresso feito direto com `adcli join` + `sssd.conf` escrito pelo script (é o que o `realm` faz por baixo). E o `wait_for` passou a ter prazo real em segundos e limite de 20 s por tentativa, para nenhum comando travado segurar o provisionamento |

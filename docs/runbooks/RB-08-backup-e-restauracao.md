# RB-08 — Backup e restauração

| | |
|---|---|
| **Objetivo** | Saber o que tem backup, conferir se está rodando e restaurar |
| **Onde** | dc01 e fs01 |
| **Automação** | [`backup-dc`](../../provision/files/bin/backup-dc) e [`restaurar-dc`](../../provision/files/bin/restaurar-dc), agendados pelo `backup-dc.timer` |
| **Testado** | Sim, automaticamente: [`tests/backup-drill.sh`](../../tests/backup-drill.sh) — resultado em [evidencias/teste-restauracao-backup.log](../evidencias/teste-restauracao-backup.log) |

## O que tem backup

| O quê | Como | Quando | Onde | Retenção |
|---|---|---|---|---|
| AD (banco, SYSVOL, configuração, Kerberos) + DHCP (config e concessões) | `backup-dc` (a frio) | todo dia 02:30 | dc01: `/var/backups/dc01/` | 7 cópias |
| Configuração de todas as máquinas | Git (este repositório) | a cada commit | GitHub | todo o histórico |
| Arquivos dos usuários (fs01) | `tar` manual (abaixo) | sob demanda | fs01: `/var/backups/fs01/` | — |

> ⚠️ **Limitação conhecida do laboratório:** o backup fica **no mesmo disco** do servidor. Se a VM for perdida, o backup vai junto. Na vida real, a regra é **3-2-1**: 3 cópias, em 2 mídias diferentes, 1 fora do local (outro prédio/nuvem). Evolução natural: copiar `/var/backups` para outro servidor ou para um bucket.

## Por que "a frio"

O `backup-dc` para o `samba-ad-dc` e o `kea` por ~2 segundos, copia preservando ACLs e atributos estendidos (essenciais para o SYSVOL) e religa. Cópia com o banco aberto poderia sair corrompida. O `samba-tool domain backup` existe, mas serve para **criar um DC novo com outro nome**, não para devolver o mesmo dc01 — ver [D10](../03-decisoes-de-arquitetura.md#d10--backup-a-frio-do-ad).

> Se o backup cair num horário em que alguém usa o sistema, a parada de 2 s não chega a ser percebida (logins prontos continuam valendo). O alerta `ServicoParado` exige 30 s parado, então não dispara.

## 1. Conferir se o backup está rodando

```bash
systemctl list-timers backup-dc.timer           # próxima e última execução
journalctl -u backup-dc --since "2 days ago"    # saída das últimas execuções
ls -lh /var/backups/dc01/
```

Esperado: um arquivo `dc01-AAAAMMDD-HHMMSS.tar.gz` (+ `.sha256`) por dia, no máximo 7.

## 2. Fazer um backup agora (antes de uma mudança arriscada)

```bash
sudo backup-dc
```

## 3. Restaurar o AD

Use quando: algo foi apagado/alterado por engano e não há outro DC, ou o banco corrompeu (`samba-tool dbcheck` com erros que `--fix` não resolve).

> ⚠️ Tudo que mudou no AD **depois** do backup se perde (contas criadas, senhas trocadas). Combine com quem pediu antes.

```bash
ls -lt /var/backups/dc01/                                             # escolha o backup
sudo restaurar-dc /var/backups/dc01/dc01-20261026-021500.tar.gz       # confere sha256, guarda o estado atual e restaura
sudo samba-tool dbcheck --cross-ncs                                   # "0 errors"
sudo /opt/homelab/tests/dc-checks.sh
```

O estado de antes da restauração fica em `/var/backups/dc01/antes-restauracao-*`, para o caso de arrependimento.

Depois de restaurar, confira o fs01 e as estações: se a restauração voltou a um ponto anterior a uma troca automática de senha da conta de computador (a cada 30 dias), o membro pode perder a confiança. Teste com `net ads testjoin` no fs01; se falhar, refaça o ingresso (`net ads join -U Administrator`).

## 4. Backup e restauração dos arquivos (fs01)

```bash
# backup
mkdir -p /var/backups/fs01
tar --xattrs --xattrs-include='*' --acls -czf /var/backups/fs01/arquivos-$(date +%F).tar.gz /srv/compartilhamentos

# restaurar UM arquivo apagado (ex.: planilha do Financeiro)
tar -tzf /var/backups/fs01/arquivos-2026-10-26.tar.gz | grep -i planilha
tar --xattrs --xattrs-include='*' --acls -xzf /var/backups/fs01/arquivos-2026-10-26.tar.gz \
    -C / srv/compartilhamentos/Financeiro/planilha.xlsx
```

`--acls --xattrs` é obrigatório: sem eles o arquivo volta sem as permissões dos grupos.

## 5. Teste de restauração (faça periodicamente)

Backup que nunca foi restaurado é só esperança. No host:

```bash
bash tests/backup-drill.sh
```

Ele faz backup, apaga a `carla.mendes`, restaura e confere se ela voltou com os mesmos grupos.

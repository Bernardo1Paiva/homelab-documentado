# =============================================================================
#  Prometheus — mon01.corp.lab
#  Gerado por provision/mon01.sh. Para adicionar um alvo novo veja
#  docs/runbooks/RB-06-monitoramento.md
#  Todo alvo leva o rótulo "host": é ele que liga os alertas de uma mesma
#  máquina (ver inhibit_rules no alertmanager.yml).
# =============================================================================
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    ambiente: homelab-corp-lab

rule_files:
  - /etc/prometheus/rules/*.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["localhost:9093"]

scrape_configs:
  # Métricas do sistema operacional de cada máquina (CPU, RAM, disco e
  # estado dos serviços systemd)
  - job_name: node
    static_configs:
      - targets: ["dc01.{{LAB_DOMAIN}}:9100"]
        labels: { host: dc01, papel: controlador-de-dominio }
      - targets: ["fs01.{{LAB_DOMAIN}}:9100"]
        labels: { host: fs01, papel: servidor-de-arquivos }
      - targets: ["mon01.{{LAB_DOMAIN}}:9100"]
        labels: { host: mon01, papel: monitoramento }

  # "Está respondendo ping?" — por IP, para não depender do DNS
  - job_name: ping
    metrics_path: /probe
    params: { module: [icmp] }
    static_configs:
      - targets: ["{{DC01_IP}}"]
        labels: { host: dc01 }
      - targets: ["{{FS01_IP}}"]
        labels: { host: fs01 }
      - targets: ["{{MON01_IP}}"]
        labels: { host: mon01 }
    relabel_configs: &blackbox_relabel
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115

  # "As portas dos serviços aceitam conexão?"
  - job_name: servicos-tcp
    metrics_path: /probe
    params: { module: [tcp_connect] }
    static_configs:
      - targets: ["{{DC01_IP}}:88"]
        labels: { host: dc01, servico: kerberos }
      - targets: ["{{DC01_IP}}:389"]
        labels: { host: dc01, servico: ldap }
      - targets: ["{{DC01_IP}}:445"]
        labels: { host: dc01, servico: smb-dc }
      - targets: ["{{FS01_IP}}:445"]
        labels: { host: fs01, servico: smb-arquivos }
    relabel_configs: *blackbox_relabel

  # "O DNS do domínio responde de verdade?" (consulta real, não só a porta)
  - job_name: dns
    metrics_path: /probe
    params: { module: [dns_dominio] }
    static_configs:
      - targets: ["{{DC01_IP}}:53"]
        labels: { host: dc01, servico: dns }
    relabel_configs: *blackbox_relabel

  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]
        labels: { host: mon01 }

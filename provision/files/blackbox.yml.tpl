# Blackbox Exporter — testes "de fora", como um usuário enxergaria o serviço
modules:
  icmp:
    prober: icmp
    timeout: 3s
    icmp:
      preferred_ip_protocol: ip4

  tcp_connect:
    prober: tcp
    timeout: 3s
    tcp:
      preferred_ip_protocol: ip4

  dns_dominio:
    prober: dns
    timeout: 3s
    dns:
      transport_protocol: udp
      preferred_ip_protocol: ip4
      query_name: "_ldap._tcp.{{LAB_DOMAIN}}"
      query_type: SRV
      valid_rcodes: [NOERROR]
      validate_answer_rrs:
        fail_if_not_matches_regexp:
          - ".*dc01\\.{{LAB_DOMAIN}}.*"

{
  // Kea DHCPv4 — escopo da rede corporativa CORP.LAB
  // Gerado por provision/dc01.sh a partir deste template. Não edite no servidor
  // sem atualizar o template no repositório (veja docs/runbooks/RB-03-dhcp.md).
  "Dhcp4": {
    "interfaces-config": {
      "interfaces": [ "{{LAN_IF}}" ],
      "dhcp-socket-type": "raw"
    },
    "control-socket": {
      "socket-type": "unix",
      "socket-name": "/run/kea/kea4-ctrl-socket"
    },
    "lease-database": {
      "type": "memfile",
      "persist": true,
      "name": "/var/lib/kea/kea-leases4.csv",
      "lfc-interval": 3600
    },
    "authoritative": true,
    "valid-lifetime": {{DHCP_LEASE_SECONDS}},
    "renew-timer": 14400,
    "rebind-timer": 25200,
    "option-data": [
      { "name": "domain-name-servers", "data": "{{DC01_IP}}" },
      { "name": "domain-name",         "data": "{{LAB_DOMAIN}}" },
      { "name": "domain-search",       "data": "{{LAB_DOMAIN}}" },
      { "name": "ntp-servers",         "data": "{{DC01_IP}}" }
    ],
    "subnet4": [
      {
        "id": 1,
        "subnet": "{{LAB_NET_CIDR}}",
        "pools": [ { "pool": "{{DHCP_POOL_START}} - {{DHCP_POOL_END}}" } ],
        "reservations": [
          {
            "hw-address": "{{PRINTER_MAC}}",
            "ip-address": "{{PRINTER_IP}}",
            "hostname": "impressora01"
          }
        ]
      }
    ],
    "loggers": [
      {
        "name": "kea-dhcp4",
        "output_options": [ { "output": "syslog" } ],
        "severity": "INFO"
      }
    ]
  }
}

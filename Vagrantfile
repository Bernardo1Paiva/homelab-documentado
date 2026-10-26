# -*- mode: ruby -*-
# vi: set ft=ruby :
# =============================================================================
#  Homelab CORP.LAB — 4 máquinas virtuais que imitam a TI de uma pequena empresa
#
#    dc01   10.10.10.10   Controlador de domínio (AD), DNS, DHCP, NTP
#    fs01   10.10.10.20   Servidor de arquivos (membro do domínio)
#    mon01  10.10.10.30   Monitoramento (Prometheus + Alertmanager)
#    ws01   DHCP          Estação de um funcionário (cliente do domínio)
#
#  Subir tudo:      vagrant up            (~15–25 min na primeira vez)
#  Testar:          vagrant ssh ws01 -c "sudo /opt/homelab/tests/smoke-test.sh"
#  Desligar:        vagrant halt          Apagar tudo: vagrant destroy -f
#  Detalhes:        docs/runbooks/RB-00-subir-o-laboratorio.md
# =============================================================================

Vagrant.require_version ">= 2.4.0"

BOX     = "bento/ubuntu-24.04"
LAB_NET = "corp-lan"            # rede interna do VirtualBox (isolada do seu Wi-Fi)

# A ordem importa: o dc01 sobe primeiro porque os outros dependem dele.
MACHINES = [
  { name: "dc01",  mac: "080027AA0010", memory: 1024, cpus: 1 },
  { name: "fs01",  mac: "080027AA0020", memory: 768,  cpus: 1 },
  { name: "mon01", mac: "080027AA0030", memory: 1024, cpus: 1,
    ports: { 9090 => 9090, 9093 => 9093 } },   # Prometheus e Alertmanager no seu navegador
  { name: "ws01",  mac: "080027AA0101", memory: 768,  cpus: 1 },
]

Vagrant.configure("2") do |config|
  config.vm.box              = BOX
  config.vm.box_check_update = false
  # Sem pasta compartilhada: os scripts vão por cópia (não depende de Guest Additions)
  config.vm.synced_folder ".", "/vagrant", disabled: true

  MACHINES.each do |m|
    config.vm.define m[:name] do |node|
      node.vm.hostname = m[:name]

      node.vm.provider "virtualbox" do |vb|
        vb.name         = "homelab-#{m[:name]}"
        vb.memory       = m[:memory]
        vb.cpus         = m[:cpus]
        vb.linked_clone = true
        vb.customize ["modifyvm", :id, "--groups", "/homelab-corp-lab"]
        # Placa 1 = NAT do Vagrant (internet e "vagrant ssh").
        # Placa 2 = rede corporativa: "Rede interna" corp-lan, com MAC fixo
        # para o script identificar a placa e o DHCP reconhecer a máquina.
        vb.customize ["modifyvm", :id,
                      "--nic2", "intnet", "--intnet2", LAB_NET,
                      "--macaddress2", m[:mac], "--nicpromisc2", "allow-all",
                      "--cableconnected2", "on"]
      end

      (m[:ports] || {}).each do |guest, host|
        node.vm.network "forwarded_port", guest: guest, host: host, host_ip: "127.0.0.1"
      end

      # Copia scripts e testes para a VM e roda o script da máquina
      node.vm.provision "shell", name: "preparar", inline: "rm -rf /tmp/homelab && mkdir -p /tmp/homelab"
      node.vm.provision "file", source: "provision", destination: "/tmp/homelab/provision"
      node.vm.provision "file", source: "tests",     destination: "/tmp/homelab/tests"
      mac_colon = m[:mac].scan(/../).join(":").downcase
      node.vm.provision "shell", name: "provisionar #{m[:name]}",
        env: { "LAN_MAC" => mac_colon },
        inline: <<~SHELL
          set -e
          rm -rf /opt/homelab && mkdir -p /opt/homelab
          cp -r /tmp/homelab/provision /tmp/homelab/tests /opt/homelab/
          # Proteção: se o Git do Windows converteu os arquivos para CRLF
          find /opt/homelab -type f -exec sed -i 's/\\r$//' {} +
          chmod +x /opt/homelab/provision/*.sh /opt/homelab/provision/files/bin/* /opt/homelab/tests/*.sh
          bash /opt/homelab/provision/#{m[:name]}.sh
        SHELL
    end
  end
end

# =============================================================================
#  /etc/samba/smb.conf — fs01 (servidor de arquivos, membro do domínio)
#  Gerado por provision/fs01.sh. Compartilhamentos ficam em
#  /etc/samba/shares.d/*.conf (um arquivo por compartilhamento).
# =============================================================================
[global]
   workgroup = {{LAB_NETBIOS}}
   realm = {{LAB_REALM}}
   security = ADS
   server role = member server
   disable netbios = yes
   smb ports = 445
   server min protocol = SMB2_10

   # Kerberos/keytab gerenciados pelo próprio Samba
   kerberos method = secrets and keytab
   dedicated keytab file = /etc/krb5.keytab

   # Mapeamento de IDs: "rid" gera o mesmo UID/GID em qualquer servidor
   # membro, sem precisar de atributos Unix no AD.
   idmap config * : backend = tdb
   idmap config * : range = 3000-7999
   idmap config {{LAB_NETBIOS}} : backend = rid
   idmap config {{LAB_NETBIOS}} : range = 10000-999999

   winbind use default domain = yes
   winbind refresh tickets = yes
   winbind offline logon = yes
   winbind enum users = no
   winbind enum groups = no
   template shell = /bin/bash
   template homedir = /home/%U

   # Permissões estilo Windows (ACL NTFS) guardadas em atributos estendidos
   vfs objects = acl_xattr
   map acl inherit = yes
   store dos attributes = yes

   # Usuário só enxerga os compartilhamentos a que tem acesso
   access based share enum = yes

   # Auditoria básica de autenticação no log
   log file = /var/log/samba/log.%m
   max log size = 10000
   log level = 1 auth_audit:3

   include = /etc/samba/shares.conf

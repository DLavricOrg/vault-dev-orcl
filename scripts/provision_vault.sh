#!/usr/bin/env bash

# check for tools we need
which curl wget unzip jq &>/dev/null || {
  yum install -y curl wget unzip jq
}

# VAULT and PLUGIN variable, are set by in Vagrantfile
# if not set, we go for the latest version

[ "${VAULT}" ] || {
  VAULT=$(curl -sL https://releases.hashicorp.com/vault/index.json | jq -r '.versions[].version' | sort -V | egrep -v 'ent|beta|rc|alpha' | tail -n1)
}

[ "${PLUGIN}" ] || {
  PLUGIN=$(curl -sL https://releases.hashicorp.com/vault-plugin-database-oracle/index.json | jq -r '.versions[].version' | sort -V | egrep -v 'ent|beta|rc|alpha' | tail -n1)
}

cp /vagrant/sw/hosts /etc/hosts
echo 'vault.test' > /etc/hostname
hostname vault.test

export PATH=/usr/local/bin:${PATH}

cd /usr/local/bin
[ -f vault_${VAULT}_linux_amd64.zip ] || {
  wget https://releases.hashicorp.com/vault/${VAULT}/vault_${VAULT}_linux_amd64.zip
}

unzip -o vault_${VAULT}_linux_amd64.zip

[ -f /etc/vault.d/server.hcl ] || {
  curl -sL https://raw.githubusercontent.com/kikitux/curl-bash/master/vault-dev-inmem/vault.sh | bash
}

yes | cp  /vagrant/sw/vault.service /etc/systemd/system/vault.service

systemctl daemon-reload
systemctl restart vault

# PLUGIN
mkdir -p /usr/local/vault/plugins
cd /usr/local/vault/plugins
[ -f vault-plugin-database-oracle_${PLUGIN}_linux_amd64.zip ] || {
  wget https://releases.hashicorp.com/vault-plugin-database-oracle/${PLUGIN}/vault-plugin-database-oracle_${PLUGIN}_linux_amd64.zip
}

unzip -o vault-plugin-database-oracle_${PLUGIN}_linux_amd64.zip
SHA256=`sha256sum vault-plugin-database-oracle | cut -d' ' -f1`

cp /root/.vault-token /home/vagrant/.vault-token
chown -R vagrant: /home/vagrant/.vault-token
export VAULT_ADDR=http://localhost:8200

vault write sys/plugins/catalog/database/oracle-database-plugin \
  sha256="${SHA256}" \
  command=vault-plugin-database-oracle

# create user
PASSWORD=${PASSWORD:-tiger}
. /vagrant/sw/instantclient.env
sqlplus system/password@//db.test:1521/XEPDB1 <<EOF
@/vagrant/sw/create_user.sql
alter user scott identified by "${PASSWORD}";
EOF

vault write database/config/my-oracle-database \
  plugin_name=oracle-database-plugin \
  connection_url="system/password@db.test:1521/XEPDB1" \
  allowed_roles="my-role" \

vault write database/roles/my-role \
  db_name=my-oracle-database \
  creation_statements='CREATE USER {{username}} IDENTIFIED BY "{{password}}"; GRANT CONNECT TO {{username}}; GRANT CREATE SESSION TO {{username}};' \
  default_ttl="1h" \
  max_ttl="24h"

  
VAULT_ADDR=http://127.0.0.1:8200 vault read database/creds/my-role

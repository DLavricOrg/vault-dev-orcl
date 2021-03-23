#!/usr/bin/env bash

SHA256=`sha256sum /usr/local/vault/plugins/vault-plugin-database-oracle | cut -d' ' -f1`

export VAULT_ADDR=http://localhost:8200

vault write sys/plugins/catalog/database/oracle-database-plugin \
  sha256="${SHA256}" \
  command=vault-plugin-database-oracle

for i in {1..60}; do
  vault write database/config/my-oracle-database${i} \
    plugin_name=oracle-database-plugin \
    connection_url="system/password@db.test:1521/XEPDB1" \
    allowed_roles="my-role${i}" \
    max_open_connections="8" \
    max_idle_connections="0" \
    max_connection_lifetime="0s"

  vault read database/config/my-oracle-database${i}

  vault write database/roles/my-role${i} \
    db_name=my-oracle-database${i} \
    creation_statements='CREATE USER {{username}} IDENTIFIED BY "{{password}}"; GRANT CONNECT TO {{username}}; GRANT CREATE SESSION TO {{username}};' \
    default_ttl="1h" \
    max_ttl="24h" \

  vault read database/roles/my-role${i}

done

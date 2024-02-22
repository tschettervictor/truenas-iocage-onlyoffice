#!/bin/sh
# Build an iocage jail under TrueNAS 13.0 and install OnlyOffice Document Server
# git clone https://github.com/tschettervictor/truenas-iocage-onlyoffice

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

#####
#
# General configuration
#
#####

# Initialize defaults
JAIL_IP=""
JAIL_INTERFACES=""
DEFAULT_GW_IP=""
INTERFACE="vnet0"
VNET="on"
JAIL_NAME="onlyoffice"
CONFIG_NAME="onlyoffice-config"
DATABASE="postgres"
DB_NAME="onlyoffice"
DB_USER="onlyoffice"
DB_ROOT_PASSWORD=$(openssl rand -base64 15)
DB_PASSWORD=$(openssl rand -base64 15)
RABBITMQ_USER="onlyoffice"
RABBITMQ_PASSWORD=$(openssl rand -base64 15)

# Check for onlyoffice-config and set configuration
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
if ! [ -e "${SCRIPTPATH}"/"${CONFIG_NAME}" ]; then
  echo "${SCRIPTPATH}/${CONFIG_NAME} must exist."
  exit 1
fi
. "${SCRIPTPATH}"/"${CONFIG_NAME}"
INCLUDES_PATH="${SCRIPTPATH}"/includes

JAILS_MOUNT=$(zfs get -H -o value mountpoint $(iocage get -p)/iocage)
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"
# If release is 13.1-RELEASE, change to 13.2-RELEASE
if [ "${RELEASE}" = "13.1-RELEASE" ]; then
  RELEASE="13.2-RELEASE"
fi

#####
#
# Input/Config Sanity checks
#
#####

# Check that necessary variables were set by guacamole-config
if [ -z "${JAIL_IP}" ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z "${JAIL_INTERFACES}" ]; then
  echo 'JAIL_INTERFACES not set, defaulting to: vnet0:bridge0'
JAIL_INTERFACES="vnet0:bridge0"
fi
if [ -z "${DEFAULT_GW_IP}" ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi

# Extract IP and netmask, sanity check netmask
IP=$(echo ${JAIL_IP} | cut -f1 -d/)
NETMASK=$(echo ${JAIL_IP} | cut -f2 -d/)
if [ "${NETMASK}" = "${IP}" ]
then
  NETMASK="24"
fi
if [ "${NETMASK}" -lt 8 ] || [ "${NETMASK}" -gt 30 ]
then
  NETMASK="24"
fi

#####
#
# Jail Creation
#
#####

# List packages to be auto-installed after jail creation
cat <<__EOF__ >/tmp/pkg.json
{
  "pkgs": [
  "nano",
  "onlyoffice-documentserver",
  "postgresql15-server",
  "postgresql15-client"
  ]
}
__EOF__

# Create the jail and install previously listed packages
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" interfaces="${JAIL_INTERFACES}" ip4_addr="${INTERFACE}|${IP}/${NETMASK}" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"
then
        echo "Failed to create jail"
        exit 1
fi
rm /tmp/pkg.json

#####
#
# Directory Creation and Mounting
#
#####

iocage exec "${JAIL_NAME}" mkdir -p /mnt/includes
iocage fstab -a "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0

#####
#
# Database Installation
#
#####

iocage exec "${JAIL_NAME}" sysrc postgresql_enable="YES"
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/pgpass /root/.pgpass
iocage exec "${JAIL_NAME}" chmod 600 /root/.pgpass
iocage exec "${JAIL_NAME}" mkdir -p /var/db/postgres
iocage exec "${JAIL_NAME}" chown postgres /var/db/postgres/
iocage exec "${JAIL_NAME}" service postgresql initdb
iocage exec "${JAIL_NAME}" service postgresql start
iocage exec "${JAIL_NAME}" sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.pgpass
  if ! iocage exec "${JAIL_NAME}" psql -U postgres -c "CREATE DATABASE ${DB_NAME};"
    then
      echo "Failed to create PostgreSQL database, aborting"
      exit 1
  fi
iocage exec "${JAIL_NAME}" psql -U postgres -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
iocage exec "${JAIL_NAME}" psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
iocage exec "${JAIL_NAME}" psql -U postgres -c "ALTER DATABASE ${DB_NAME} OWNER to ${DB_USER};"
iocage exec "${JAIL_NAME}" "psql -hlocalhost -U${DB_USER} -d ${DB_NAME} -f /usr/local/www/onlyoffice/documentserver/server/schema/postgresql/createdb.sql"
iocage exec "${JAIL_NAME}" psql -U postgres -c "SELECT pg_reload_conf();"
iocage exec "${JAIL_NAME}" sed -i '' "/dbPass/s|onlyoffice|${DB_PASSWORD}|" /usr/local/etc/onlyoffice/documentserver/local.json
iocage exec "${JAIL_NAME}" sed -i '' "1,/inbox/s|false|true|" /usr/local/etc/onlyoffice/documentserver/local.json
iocage exec "${JAIL_NAME}" sed -i '' "1,/outbox/s|false|true|" /usr/local/etc/onlyoffice/documentserver/local.json
iocage exec "${JAIL_NAME}" sed -i '' "1,/browser/s|false|true|" /usr/local/etc/onlyoffice/documentserver/local.json
iocage exec "${JAIL_NAME}" sed -i '' "1,/rejectUnauthorized/s|true|false|" /usr/local/etc/onlyoffice/documentserver/default.json

#####
#
# RabbitMQ Installation
#
#####

iocage exec "${JAIL_NAME}" sysrc rabbitmq_enable="YES"
iocage exec "${JAIL_NAME}" service rabbitmq start
iocage exec "${JAIL_NAME}" rabbitmqctl --erlang-cookie $(iocage exec "${JAIL_NAME}" cat /var/db/rabbitmq/.erlang.cookie) add_user ${RABBITMQ_USER} ${RABBITMQ_PASSWORD}
iocage exec "${JAIL_NAME}" rabbitmqctl --erlang-cookie $(iocage exec "${JAIL_NAME}" cat /var/db/rabbitmq/.erlang.cookie) set_user_tags ${RABBITMQ_USER} administrator
iocage exec "${JAIL_NAME}" rabbitmqctl --erlang-cookie $(iocage exec "${JAIL_NAME}" cat /var/db/rabbitmq/.erlang.cookie) set_permissions -p /  ${RABBITMQ_USER} ".*" ".*" ".*"
iocage exec "${JAIL_NAME}" sed -i '' -e "s|guest:guest@localhost|${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@localhost|g" /usr/local/etc/onlyoffice/documentserver/local.json
iocage exec "${JAIL_NAME}" service rabbitmq restart

#####
#
# Nginx Installation
#
#####

iocage exec "${JAIL_NAME}" sysrc nginx_enable="YES"
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/nginx/conf.d
iocage exec "${JAIL_NAME}" cp /usr/local/etc/onlyoffice/documentserver/nginx/ds.conf /usr/local/etc/nginx/conf.d/.
iocage exec "${JAIL_NAME}" sed -i '' -e '40s/^/    include \/usr\/local\/etc\/nginx\/conf.d\/*.conf;\n/g' /usr/local/etc/nginx/nginx.conf
iocage exec "${JAIL_NAME}" sed -i '' '4d' /usr/local/etc/nginx/conf.d/ds.conf
iocage exec "${JAIL_NAME}" service nginx restart

#####
#
# Supervisord Installation
#
#####

iocage exec "${JAIL_NAME}" sysrc supervisord_enable="YES"
iocage exec "${JAIL_NAME}" "echo '[include]' >> /usr/local/etc/supervisord.conf"
iocage exec "${JAIL_NAME}" "echo 'files = /usr/local/etc/onlyoffice/documentserver/supervisor/*.conf' >> /usr/local/etc/supervisord.conf"
iocage exec "${JAIL_NAME}" sed -i "" -e 's|/tmp/supervisor.sock|/var/run/supervisor/supervisor.sock|g' /usr/local/etc/supervisord.conf
iocage exec "${JAIL_NAME}" /usr/local/bin/documentserver-pluginsmanager.sh --update=/usr/local/www/onlyoffice/documentserver/sdkjs-plugins/plugin-list-default.json

#####
#
# Save Passwords/Finalize Installation
#
#####
echo "${DATABASE} root user is root and password is ${DB_ROOT_PASSWORD}" > /root/${JAIL_NAME}_db_password.txt
echo "OnlyOffice database user is ${DB_USER} and password is ${DB_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt
echo "RabbitMQ user is ${RABBITMQ_USER} and password is ${RABBITMQ_PASSWORD}." >> /root/${JAIL_NAME}_db_password.txt
# Don't need /mnt/includes any more, so unmount it
iocage fstab -r "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0
iocage restart "${JAIL_NAME}"

echo "---------------"
echo "Installation complete."
echo "---------------"
echo "Database Information"
echo "MySQL Username: root"
echo "MySQL Password: $DB_ROOT_PASSWORD"
echo "RabbitMQ User: $RABBITMQ_USER"
echo "RabbitMQ Password: "$RABBITMQ_PASSWORD""
echo "---------------"
echo "All passwords are saved in /root/${JAIL_NAME}_db_password.txt"
echo "---------------"

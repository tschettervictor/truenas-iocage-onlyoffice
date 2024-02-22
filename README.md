# truenas-iocage-onlyoffice
Script to create an iocage jail on TrueNAS and install OnlyOffice

## Status
This script will work with TrueNAS CORE 13.0

## Usage

### Installation
Download the repository to a convenient directory on your TrueNAS system by changing to that directory and running `git clone https://github.com/tschettervictor/truenas-iocage-onlyoffice`.  Then change into the new `truenas-iocage-onlyoffice` directory and create a file called `onlyoffice-config` with your favorite text editor.  In its minimal form, it would look like this:
```
JAIL_IP="192.168.1.199"
DEFAULT_GW_IP="192.168.1.1"
```
Many of the options are self-explanatory, and all should be adjusted to suit your needs, but only a few are mandatory.  The mandatory options are:

* JAIL_IP is the IP address for your jail.  You can optionally add the netmask in CIDR notation (e.g., 192.168.1.199/24).  If not specified, the netmask defaults to 24 bits.  Values of less than 8 bits or more than 30 bits are invalid.
* DEFAULT_GW_IP is the address for your default gateway
 
In addition, there are some other options which have sensible defaults, but can be adjusted if needed.  These are:

* JAIL_NAME: The name of the jail, defaults to "uptimekuma"
* INTERFACE: The network interface to use for the jail.  Defaults to `vnet0`.
* JAIL_INTERFACES: Defaults to `vnet0:bridge0`, but you can use this option to select a different network bridge if desired.  This is an advanced option; you're on your own here.
* VNET: Whether to use the iocage virtual network stack.  Defaults to `on`.

### Execution
Once you've downloaded the script and prepared the configuration file, run this script (`script onlyoffice.log ./onlyoffice-jail.sh`).  The script will run for maybe a minute.  When it finishes, your jail will be created and uptimekuma will be installed.

### Notes
- This script will configure OnlyOffice to run on Nginx port 80 for use behind a reverse proxy
- This script is primarily put together for use with nextcloud
- This script sets the "rejectUnauthorized" field to false instead of true
- This script uses the default "secret" token. If you want to change it, you need to change it in `/usr/local/etc/onlyoffice/documentserver/local.json` and also set it in the the OnlyOffice settings in nextcloud

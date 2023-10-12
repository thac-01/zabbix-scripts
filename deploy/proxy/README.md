# Zabbix_Script



## Zabbix Proxy Automation

### Requirement
* CPU = 2 Core
* Memory = 4GB Ram
* Storage = 30 GB

### Default installation
* PostgreSQL-15
* Zabbix Proxy version 6 LTS
* Zabbix Agent 2

This script automatically deploys the zabbix_proxy.

The script will check the version and automatically install the correct packages.

OS Supported:
| OS        | Support Status |
|-----------|----------------|
| Debian 12 | OK / Tested    |
| Debian 11 | OK             |
| Debian 10 | OK             |
| Ubuntu 22.04 |  OK / Tested |
| Ubuntu 20.04 |  OK   |
| Ubuntu 19.04 |  OK   |
| Rhel 9 |  OK / Tested |
| Rhel 8 |  OK  |
| Oracle Linux 9 |  OK / Tested  |
| Oracle Linux 8 |  OK  |


## Installation

Run the script as the root user:

```
sudo wget https://raw.githubusercontent.com/thac-01/zabbix-script/main/deploy/proxy/deploy-proxy.sh -O deploy-proxy.sh
sudo bash deploy-proxy.sh
```

## Remove

Run the script as the root user:

```
sudo wget https://raw.githubusercontent.com/thac-01/zabbix-script/main/deploy/proxy/remove-proxy.sh -O remove-proxy.sh
sudo bash remove-proxy.sh
```

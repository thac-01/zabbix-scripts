#!/bin/bash

set -e

# Funzione per verificare l'esito di un comando
check_command_result() {
    if [ $? -ne 0 ]; then
        echo "[Error] Error during command execution. Script aborted."
        exit 1
    fi
}

# Verifica che lo script sia eseguito come root
if [ "$EUID" -ne 0 ]; then
    echo "[Error] This script must be run as root."
    exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    exit 1
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    . /etc/redhat-release
    OS=$REDHAT_SUPPORT_PRODUCT
    VER=$REDHAT_SUPPORT_PRODUCT_VERSION
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi
check_command_result
echo "[Info] Operating system detected: $OS"
echo "[Info] Version detected: $VER"

#Variabili
defremove_base_packages="N"

# Richiesta controllo repo
echo "DEB distro base packages: git python3-pip net-tools snmp snmp-mibs-downloader apt-transport-https"
echo "RPM distro base packages: git python3-pip net-tools net-snmp net-snmp-utils"
read -p "[Info] Do you want to remove base packages? [$defremove_base_packages]/y: " remove_base_packages

# Assegnazione del valore predefinito se la variabile è vuota
if [ -z "$remove_base_packages" ]; then
    remove_base_packages="$defremove_base_packages"
fi

#Attesa prima di eseguire lo script
echo "[Attention] All data contained on the DB will be destroyed!"
echo "Press enter to continue..."
read

for ((i=5; i>=1; i--)); do
    echo "[Info] The script will start in $i second/s"
    echo "press CTRL+C to abort"
    sleep 1
done

# Verifica se il sistema operativo è supportato
if [ "$OS" == "Debian GNU/Linux" ] || [ "$OS" == "Ubuntu" ]; then
    if [[ "$OS" == "Debian GNU/Linux" && "$VER" == "12" ]] || [[ "$OS" == "Debian GNU/Linux" && "$VER" == "11" ]] || [[ "$VER" == "10" ]] || [[ "$OS" == "Ubuntu" && "$VER" == "22.04" ]] || [[ "$OS" == "Ubuntu" && "$VER" == "20.04" ]]; then
        
        # Rimozione dei pacchetti base se richiesto dall'utente
        if [[ "$remove_base_packages" == "Y" || "$remove_base_packages" == "y" ]]; then
            if dpkg -s git python3-pip net-tools snmp snmp-mibs-downloader apt-transport-https >/dev/null 2>&1; then
                apt remove -y git python3-pip net-tools snmp snmp-mibs-downloader apt-transport-https
                check_command_result
            else
                echo "[Info] Some basic packages are not installed."
            fi
        fi
        
        # Rimozione di Zabbix Release e Repository
        if dpkg -s zabbix-release >/dev/null 2>&1; then
            apt autoremove --purge -y zabbix-release
            check_command_result
            echo "[Success] The Zabbix Release package has been removed."
        else
            echo "[Info] Zabbix Release package is not installed."
        fi

        # Rimozione di Zabbix Agent2
        if dpkg -s zabbix-agent2 >/dev/null 2>&1; then
            apt autoremove --purge -y zabbix-agent2 zabbix-agent2-plugin-*
            check_command_result
            echo "[Success] The Zabbix Agent2 package has been removed."
        else
            echo "[Info] Zabbix Agent2 package is not installed."
        fi
        
        # Rimozione di Zabbix Proxy
        if dpkg -s zabbix-proxy-pgsql >/dev/null 2>&1; then
            apt autoremove --purge -y zabbix-proxy-pgsql zabbix-sql-scripts
            rm -f /etc/zabbix/zabbix_proxy.conf
            check_command_result
            echo "[Success] The Zabbix Proxy package has been removed."
        else
            echo "[Info] The Zabbix Proxy package is not installed."
        fi
        
        # Rimozione di PostgreSQL
        if dpkg -s postgresql-15 >/dev/null 2>&1; then
            apt autoremove --purge -y postgresql-15
            check_command_result
            echo "[Success] The Zabbix PostgreSQL package has been removed."
        else
            echo "[Info] The PostgreSQL package is not installed."
        fi

        # Rimozione repo

        rm -rf /etc/apt/sources.list.d/pgdg.list
        rm -rf /etc/apt/trusted.gpg.d/pgdg.asc
        check_command_result
        echo "[Success] PostgreSQL repositories removed"

        rm -rf /etc/apt/sources.list.d/zabbix*
        check_command_result
        echo "[Success] Zabbix repositories removed"

    else
        echo "[Error] $OS $VER unsupported."
        exit 1
    fi
elif [[ "$OS" == "Oracle Linux Server" || "$OS" == "RedHat Linux Server" ]]; then
    rhel_version=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    if [ "$rhel_version" == "9" ] || [ "$rhel_version" == "8" ]; then 
        # Comandi specifici per RHEL 8, 9
        # ...
        
        # Rimozione dei pacchetti base se richiesto dall'utente
        if [[ "$remove_base_packages" == "Y" || "$remove_base_packages" == "y" ]]; then
            if rpm -q git python3-pip htop net-tools snmp snmp-mibs-downloader >/dev/null 2>&1; then
                dnf autoremove -y git python3-pip net-tools net-snmp net-snmp-utils
                check_command_result
            else
                echo "[Info] Some basic packages are not installed."
            fi
        fi
        
        # Rimozione di Zabbix Agent2
        if rpm -q zabbix-agent2 >/dev/null 2>&1; then
            dnf autoremove -y zabbix-agent2 zabbix-agent2-plugin-*
            check_command_result
        else
            echo "[Info] Zabbix Agent2 package is not installed."
        fi
        
        # Rimozione di Zabbix Proxy
        if rpm -q zabbix-proxy-pgsql >/dev/null 2>&1; then
            dnf autoremove -y zabbix-proxy-pgsql zabbix-sql-scripts zabbix-release
            rm -f /etc/zabbix/zabbix_proxy.conf
            check_command_result
        else
            echo "[Info] The Zabbix Proxy package is not installed."
        fi
        
        # Rimozione di PostgreSQL
        if rpm -q postgresql15 >/dev/null 2>&1; then
            dnf autoremove -y postgresql15
            rm -rf /var/lib/pgsql/

            check_command_result
        else
            echo "[Info] The PostgreSQL package is not installed."
        fi
    else
        echo "[Error] RHEL/Oracle Linux $VER not supported."
        exit 1
    fi
else
    echo "[Error] Operating system not supported."
    exit 1
fi

echo "[Success] Script completed successfully."
exit 0

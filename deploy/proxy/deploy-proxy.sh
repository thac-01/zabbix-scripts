#!/bin/bash

set -e

export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

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
    echo "[Error] OpenSuSe unsupported distro"
    exit 1
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    . /etc/redhat-release
    OS=$NAME
    VER=$VERSION_ID
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi
check_command_result
echo "[Info] Operating system detected:" $OS
echo "[Info] Version detected:" $VER

# Variabile predefinita
defaultproxy="zabbix_proxy"
defaultserver="10.155.32.9"
DBpassword=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 18)
DBpasswordmon=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 18)
defaultControlloRepo="Y"

# Prompt user to enter proxy name.
read -p "[Info] How do you want to rename the proxy [$defaultproxy]: " var1

# Assegnazione del valore predefinito se la variabile è vuota
if [ -z "$var1" ]; then
    var1="$defaultproxy"
fi

echo "[Success] The proxy name entered is: $var1"

# Richiesta all'utente di inserire il nome del server
read -p "[Info] Enter the IP address of the zabbix Server [$defaultserver]: " var2

# Assegnazione del valore predefinito se la variabile è vuota
if [ -z "$var2" ]; then
    var2="$defaultserver"
fi

echo "[Success] The server name entered is: $var2"

# Richiesta controllo repo
read -p "[Info] Want to check reachability to repositories? [$defaultControlloRepo]/n: " ControlloRepo

# Assegnazione del valore predefinito se la variabile è vuota
if [ -z "$ControlloRepo" ]; then
    ControlloRepo="$defaultControlloRepo"
fi

# Controllo della raggiungibilità delle repo
if [[ "$ControlloRepo" == "Y" || "$ControlloRepo" == "y" ]]; then
    repo_urls=("http://archive.ubuntu.com" "http://security.ubuntu.com" "http://repo.zabbix.com" "http://deb.debian.org" "http://security.debian.org" "https://download.postgresql.org")
    for url in "${repo_urls[@]}"; do
        if ! wget --spider "$url" >/dev/null 2>&1; then
            echo "[Error] Unable to reach repo: $url. Check the internet connection."
            exit 1
        fi
    done
    echo "[Success] All repositories are reached"
fi


#Attesa prima di eseguire lo script
for ((i=5; i>=1; i--)); do
    echo "[Info] The script will start in $i seconds/o"
    echo "press CTRL+C to abort."
    sleep 1
done


if [ "$OS" == "Debian GNU/Linux" ] || [ "$OS" == "Ubuntu" ]; then
    if [[ "$OS" == "Debian GNU/Linux" && "$VER" == "12" ]] || [[ "$OS" == "Debian GNU/Linux" && "$VER" == "11" ]] || [[ "$VER" == "10" ]] || [[ "$OS" == "Ubuntu" && "$VER" == "22.04" ]] || [[ "$OS" == "Ubuntu" && "$VER" == "20.04" ]]; then
        # Codice da eseguire per Debian

        #Cambio nomi Variabili
        if [ "$OS" == "Debian GNU/Linux" ]; then
            OS="debian"
        fi

        if [ "$OS" == "Ubuntu" ]; then
            OS="ubuntu"
        fi

        # Installazione dei pacchetti base
        if [ "$OS" == "Debian GNU/Linux" ]; then
            awk '/^deb/ && !/non-free$/ {print $0" non-free"; next} {print}' /etc/apt/sources.list > /tmp/sources.list.tmp && mv /tmp/sources.list.tmp /etc/apt/sources.list
        fi
        
        apt update
        apt install -y wget git python3 python3-pip curl sudo htop net-tools snmp snmp-mibs-downloader apt-transport-https lsb-release
        
        # Verifica se PostgreSQL è già installato
        if ! dpkg -s postgresql-15 >/dev/null 2>&1; then
            echo "[Info] PostgreSQL-15 installation in progress... wait for it"
            # Installazione di PostgreSQL
            sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
            wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/pgdg.asc &>/dev/null
            apt update
            apt install -y postgresql-15
            systemctl start postgresql
            systemctl enable postgresql
            ss -antpl | grep 5432
            check_command_result
            echo "[Success] PostgreSQL-15 installed correctly."
        else
            echo "[Warning] PostgreSQL-15 is already installed."
        fi
        
        # Verifica se Zabbix Proxy è già installato
        if ! dpkg -s zabbix-proxy-pgsql >/dev/null 2>&1; then
            echo "[Info] Zabbix Proxy installation in progress... please wait."
            # Installazione di Zabbix Proxy
            wget -P /tmp https://repo.zabbix.com/zabbix/6.0/${OS}/pool/main/z/zabbix-release/zabbix-release_latest+${OS}${VER}_all.deb
            dpkg -i /tmp/zabbix-release_latest+${OS}${VER}_all.deb
            apt update
            apt install -y zabbix-proxy-pgsql zabbix-sql-scripts
            check_command_result
            echo "[Success] Zabbix Proxy installed correctly."
        else
            echo "[Warning] Zabbix Proxy is already installed."
        fi
        
        # Verifica se Zabbix Agent2 è già installato
        if ! dpkg -s zabbix-agent2 >/dev/null 2>&1; then
            # Installazione di Zabbix Agent2
            echo "[Info] Zabbix Agent 2 installation in progress... please wait."
            apt update
            apt install -y zabbix-agent2 zabbix-agent2-plugin-*
            systemctl restart zabbix-agent2
            systemctl enable zabbix-agent2
            check_command_result
            echo "[Success] Zabbix Agent2 installed correctly."
        else
            echo "[Warning] Zabbix Agent2 is already installed."
        fi
    else
        # Codice da eseguire per altre versioni di Debian GNU/Linux
        echo "[Error] This version of Debian/Ubuntu is not supported."
        exit 1
    fi        
elif [ "$OS" == "Oracle Linux Server" ] || [ "$OS" == "RedHat Linux Server" ]; then
    # Codice da eseguire
    # ...
    if [[ -f /etc/redhat-release ]]; then
        rhel_version=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)

        if [ "$rhel_version" == "9" ] || [ "$rhel_version" == "8" ]; then    
            # Aggiornamento del sistema
            dnf update -y
            
            # Installazione dei pacchetti necessari
            dnf install -y wget git python3 python3-pip sudo curl net-tools net-snmp net-snmp-utils
        
            # Verifica se PostgreSQL è già installato
            if ! rpm -q postgresql15-server >/dev/null 2>&1; then
                echo "[Info] PostgreSQL-15 installation in progress... wait."
                # Installazione di PostgreSQL
                dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-${rhel_version}-x86_64/pgdg-redhat-repo-latest.noarch.rpm
                dnf update
                dnf install -y postgresql15-server
                /usr/pgsql-15/bin/postgresql-15-setup initdb
                systemctl enable --now postgresql-15
                ss -antpl | grep 5432
                check_command_result
                echo "[Success] PostgreSQL-15 installed correctly."
            else
                echo "[Warning] PostgreSQL-15 is already installed."
            fi
        
            # Verifica se Zabbix Proxy è già installato
            if ! rpm -q zabbix-proxy-pgsql >/dev/null 2>&1; then
                echo "[Info] Zabbix Proxy installation in progress... please wait."
                # Installazione di Zabbix Proxy
                wget -P /tmp https://repo.zabbix.com/zabbix/6.0/rhel/${rhel_version}/x86_64/zabbix-release-6.0-4.el${rhel_version}.noarch.rpm
                rpm -ivh /tmp/zabbix-release-6.0-4.el${rhel_version}.noarch.rpm
                dnf update
                dnf install -y zabbix-proxy-pgsql zabbix-sql-scripts
                check_command_result
                echo "[Success] Zabbix Proxy installed correctly."
            else
                echo "[Warning] Zabbix Proxy is already installed."
            fi
        
            # Verifica se Zabbix Agent2 è già installato
            if ! rpm -q zabbix-agent2 >/dev/null 2>&1; then
                # Installazione di Zabbix Agent2
                echo "[Info] Zabbix Agent 2 installation in progress... please wait."
                dnf update
                dnf install -y zabbix-agent2 zabbix-agent2-plugin-*
                systemctl restart zabbix-agent2
                systemctl enable zabbix-agent2
                check_command_result
                echo "[Success] Zabbix Agent2 installed correctly."
            else
                echo "[Warning] Zabbix Agent2 is already installed."
            fi
        else
            echo "[Error] This version of RedHat/Oracle is not supported."
            exit 1
        fi
    else
        # Codice da eseguire per altre versioni di RHEL
        echo "[Error] This version of RedHat/Oracle is not supported."
        exit 1
    fi
else
    # Codice da eseguire per altri sistemi operativi
    echo "[Error] This version of RedHat/Oracle is not supported."
    exit 1
fi

# Configurazione DB per Zabbix proxy
echo "[Info] Creating zabbix_proxy Database and creating zabbix user"
if sudo -u postgres psql -c "SELECT 1" >/dev/null 2>&1; then
    # Verifica se il database esiste già
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw zabbix_proxy; then
        # Il database esiste, lo cancella
        sudo -u postgres psql -c "DROP DATABASE zabbix_proxy"
        echo "[Warning] The zabbix_proxy database already existed and has been removed."
    fi
    
    # Verifica se l'utente zabbix esiste già
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='zabbix'" | grep -q 1; then
        # L'utente esiste, lo cancella
        sudo -u postgres psql -c "DROP USER zabbix"
        echo "[Warning] The user zabbix already existed and has been removed."
    fi
    
    # Verifica se l'utente zbx_monitor esiste già
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='zbx_monitor'" | grep -q 1; then
        # L'utente esiste, lo cancella
        sudo -u postgres psql -c "DROP USER zbx_monitor"
        echo "[Warning] The user zbx_monitor already existed and has been removed."
    fi
    
    echo "[Info] Creating the new user Zabbix and the new database"
    
    # Crea l'utente zabbix con password
    sudo -u postgres psql -c "CREATE USER zabbix WITH PASSWORD '$DBpassword';"
    
    # Crea l'utente zbx_monitor con password
    sudo -u postgres psql -c "CREATE USER zbx_monitor WITH PASSWORD '$DBpasswordmon';"
    sudo -u postgres psql -c "GRANT pg_monitor TO zbx_monitor"
    
    # Crea il database zabbix_proxy di proprietà dell'utente zabbix
    sudo -u postgres psql -c "CREATE DATABASE zabbix_proxy OWNER zabbix;"
    sudo -u zabbix psql zabbix_proxy < /usr/share/zabbix-sql-scripts/postgresql/proxy.sql
    
    echo "[Success] The user Zabbix, user zbx_monitor, and the zabbix_proxy database were successfully created."

    # Configuro tuning per 2 core e 4GB di RAM
    sudo -u postgres psql -c "ALTER SYSTEM SET max_connections = '500';"
    sudo -u postgres psql -c "ALTER SYSTEM SET shared_buffers = '1GB';"
    sudo -u postgres psql -c "ALTER SYSTEM SET effective_cache_size = '3GB';"
    sudo -u postgres psql -c "ALTER SYSTEM SET maintenance_work_mem = '256MB';"
    sudo -u postgres psql -c "ALTER SYSTEM SET checkpoint_completion_target = '0.9';"
    sudo -u postgres psql -c "ALTER SYSTEM SET wal_buffers = '16MB';"
    sudo -u postgres psql -c "ALTER SYSTEM SET default_statistics_target = '100';"
    sudo -u postgres psql -c "ALTER SYSTEM SET random_page_cost = '1.1';"
    sudo -u postgres psql -c "ALTER SYSTEM SET effective_io_concurrency = '300';"
    sudo -u postgres psql -c "ALTER SYSTEM SET work_mem = '873kB';"
    sudo -u postgres psql -c "ALTER SYSTEM SET huge_pages = 'off';"
    sudo -u postgres psql -c "ALTER SYSTEM SET min_wal_size = '1GB';"
    sudo -u postgres psql -c "ALTER SYSTEM SET max_wal_size = '3GB';"

else
    echo "[Error] Connection to PostgreSQL database failed. Make sure the PostgreSQL server is running and configured correctly."
    exit 1
fi


# Configurazione di Zabbix Proxy
echo "[Info] Configurazione Zabbix Proxy in corso... attendere"
proxy_conf="/etc/zabbix/zabbix_proxy.conf"
sed -i.bck "s/Server=127.0.0.1/Server=$var2/" "$proxy_conf"
sed -i.bck "s/Hostname=Zabbix proxy/Hostname=$var1/" "$proxy_conf"
sed -i.bck "s/ServerActive=127.0.0.1/ServerActive=$var2/" "$proxy_conf"
sed -i.bck "s/# DBPassword=/DBPassword=$DBpassword/" "$proxy_conf"
sed -i.bck "s/StatsAllowedIP=127.0.0.1/StatsAllowedIP=127.0.0.1,$var2/" "$proxy_conf"
sed -i.bck "s/# ProxyOfflineBuffer=1/ProxyOfflineBuffer=24/" "$proxy_conf"
sed -i.bck "s/# StartPollers=5/StartPollers=20/" "$proxy_conf"
sed -i.bck "s/# StartPreprocessors=3/StartPreprocessors=20/" "$proxy_conf"
sed -i.bck "s/# StartPollersUnreachable=1/StartPollersUnreachable=20/" "$proxy_conf"
sed -i.bck "s/# StartHistoryPollers=1/StartHistoryPollers=20/" "$proxy_conf"
sed -i.bck "s/# StartPingers=1/StartPingers=10/" "$proxy_conf"
sed -i.bck "s/# StartDiscoverers=1/StartDiscoverers=10/" "$proxy_conf"
sed -i.bck "s/# StartHTTPPollers=1/StartHTTPPollers=20/" "$proxy_conf"
sed -i.bck "s/# CacheSize=8M/CacheSize=512M/" "$proxy_conf"
sed -i.bck "s/# StartDBSyncers=4/StartDBSyncers=8/" "$proxy_conf"
sed -i.bck "s/# HistoryCacheSize=16M/HistoryCacheSize=512M/" "$proxy_conf"
sed -i.bck "s/# HistoryIndexCacheSize=4M/HistoryIndexCacheSize=512M/" "$proxy_conf"
sed -i.bck "s/# StartVMwareCollectors=0/StartVMwareCollectors=1/" "$proxy_conf"
sed -i.bck "s/Timeout=4/Timeout=30/" "$proxy_conf"
sed -i.bck "s/# ConfigFrequency=3600/ConfigFrequency=900/" "$proxy_conf"
check_command_result
echo "[Success] Zabbix Proxy Configuration Completed"


agent_conf="/etc/zabbix/zabbix_agent2.conf"
sed -i.bck "s/Server=127.0.0.1/Server=$var2/" "$agent_conf"
sed -i.bck "s/ServerActive=127.0.0.1/ServerActive=$var2/" "$agent_conf"
sed -i.bck "s/Hostname=Zabbix server/Hostname=$var1/" "$agent_conf"
sed -i.bck "s/# Timeout=3/Timeout=30/" "$agent_conf"
sed -i.bck "s/# Plugins.SystemRun.LogRemoteCommands=0/Plugins.SystemRun.LogRemoteCommands=1/" "$agent_conf"
sed -i.bck "s/# DenyKey=system.run/AllowKey=system.run/" "$agent_conf"
check_command_result
echo "[Success] Zabbix Agent 2 Configuration Completed"

sed -i '$ a\zabbix ALL=NOPASSWD: ALL' /etc/sudoers
echo "[Success] Configuration sudoers Completed"

# Restart of Zabbix Proxy
systemctl restart zabbix-proxy
systemctl enable zabbix-proxy
check_command_result

# Show variable content    
echo "[Success] Script completed successfully."
echo "[Info] Name of proxy:" $var1
echo "[Info] IP of proxy: $(hostname -I | awk '{print $1}')"
echo "[Info] The proxy will send data to the server:" $var2
echo "[Info] Database name is: zabbix_proxy" 
echo "[Info] The DB user name is: zabbix"
echo "[Info] The password of the zabbix user is:" $DBpassword
echo "[Info] The DB monitoring user is: zbx_monitor"
echo "[Info] The DB password is:" $DBpasswordmon

rm -rf deploy-proxy.sh
exit 0

import requests
import urllib3
import json
import os

# Disabilita i warning SSL
urllib3.disable_warnings()

# URL e credenziali per l'API Zabbix
zabbix_url = "https://indirizzo-ip/api_jsonrpc.php"
zabbix_username = ""
zabbix_password = ""

# Funzione per confrontare due dizionari ignorando la chiave "date"
def compare_dicts(dict1, dict2):
    if "zabbix_export" in dict1 and "zabbix_export" in dict2:
        if "date" in dict1["zabbix_export"]:
            del dict1["zabbix_export"]["date"]
        if "date" in dict2["zabbix_export"]:
            del dict2["zabbix_export"]["date"]
    return dict1 == dict2

# Funzione per eseguire richieste all'API Zabbix
def make_zabbix_api_request(data, test_credentials=False):
    headers = {"Content-Type": "application/json-rpc"}

    try:
        response = requests.post(
            zabbix_url,
            json=data,
            headers=headers,
            timeout=30,
            verify=False
        )

        # Solleva un'eccezione se la richiesta non ha avuto successo
        response.raise_for_status()

        # Se richiesto, effettua un test di autenticazione
        if test_credentials:
            if "result" in response.json() and "error" not in response.json():
                return True
            return False

        # Ritorna i dati della risposta
        return response.json()
    except requests.exceptions.RequestException as e:
        raise Exception(f"Zabbix API request failed: {str(e)}")

# Caricamento iniziale per autenticarsi
auth_payload = {
    "jsonrpc": "2.0",
    "method": "user.login",
    "params": {
        "user": zabbix_username,
        "password": zabbix_password,
    },
    "id": 1,
    "auth": None
}

# Test delle credenziali
if make_zabbix_api_request(auth_payload, test_credentials=True):
    print("Credenziali Zabbix valide.")
else:
    print("Credenziali Zabbix non valide. Verifica username e password.")
    # Gestisci il fallimento delle credenziali come desiderato.
    exit()

# Richiesta di autenticazione
auth_response = make_zabbix_api_request(auth_payload)
# Estrai l'auth_token dalla risposta
auth_token = auth_response["result"]

# Caricamento per ottenere tutte le informazioni dei host
hosts_payload = {
    "jsonrpc": "2.0",
    "method": "host.get",
    "params": {
        "output": "extend",
        "selectGroups": "extend"
    },
    "id": 2,
    "auth": auth_token
}

# Richiesta per ottenere tutte le informazioni dei host
hosts_response = make_zabbix_api_request(hosts_payload)
# Estrai i host dalla risposta
hosts = hosts_response["result"]
#print (hosts)

# Assicurati che la directory "output" esista
output_dir = "zabbixhost"
os.makedirs(output_dir, exist_ok=True)

# Ciclo attraverso ciascun host
for host in hosts:
    current_id = host["hostid"]

    # Cargo per ottenere le informazioni sul host
    host_payload = {
        "jsonrpc": "2.0",
        "method": "configuration.export",
        "params": {
            "options": {
                "hosts": [current_id]
            },
            "format": "json"
        },
        "id": 3,
        "auth": auth_token
    }
    # Richiesta per ottenere le informazioni sul host
    host_response = make_zabbix_api_request(host_payload)
    # Estrai l'output della risposta
    output = host_response["result"]
    # Converte l'output JSON in un dizionario Python
    output_dict = json.loads(output)
    #print (output_dict)

    # Trova la directory in cui salvare il host
    current_dir = "Hosts"
    try:
        for directory in output_dict["zabbix_export"]["groups"]:
            if "General" not in directory["name"]:
                current_dir = directory["name"]
    except:
        #TODO da sistemare messaggio di errore
        print (f"An error occured processing host {current_id}")
        continue

        # Crea la directory se non esiste sotto la directory "output"
    current_dir_path = os.path.join(output_dir, current_dir)
    os.makedirs(current_dir_path, exist_ok=True)

    # Estrai il nome del host
    try:
        current_host_name = output_dict["zabbix_export"]["hosts"][0]["name"]
    except:
        print (f"An error occured processing host {current_id}")
        continue

    # Costruisci il percorso del file
    path = os.path.join(current_dir_path, f"{current_host_name}.json")

    # Se il file esiste, confronta il contenuto con quello del nuovo host
    if os.path.exists(path):
        with open(path, "r") as file:
            file_data = json.load(file)

        # Se i contenuti non sono uguali, aggiorna il file
        if not compare_dicts(file_data, output_dict):
            print(f"Updated host {current_id}: {path}")
            with open(path, "w") as file:
                json.dump(output_dict, file, indent=4)  # Formatta l'output come JSON leggibile
    else:
        # Se il file non esiste, crea un nuovo file con il contenuto del host
        print(f"Creating host {current_id}: {path}")
        with open(path, "w") as file:
            json.dump(output_dict, file, indent=4)  # Formatta l'output come JSON leggibile

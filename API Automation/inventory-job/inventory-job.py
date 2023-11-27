import requests
import csv
import urllib3
import os

# Disable SSL warnings
urllib3.disable_warnings()

# Define the URL and credentials for the Zabbix API
url = "https://<ip-address>/api_jsonrpc.php"
username = ""
password = ""
auth_token = None  # Global variable to store the authentication token

# Create the authentication payload
auth_payload = {
    "jsonrpc": "2.0",
    "method": "user.login",
    "params": {
        "user": username,
        "password": password,
    },
    "id": 1,
    "auth": None
}

def zabbix_api_request(data, test_credentials=False):
    headers = {"Content-Type": "application/json-rpc"}

    try:
        response = requests.post(
            url,
            json=data,
            headers=headers,
            timeout=30,
            verify=True
        )

        response.raise_for_status()

        #print(response.json())

        if test_credentials:
            if "result" in response.json() and "error" not in response.json():
                return True
            return False

        return response.json()
    except requests.exceptions.RequestException as e:
        raise Exception(f"Zabbix API request failed: {str(e)}")

def get_all_host_ids():
    method = 'host.get'
    params = {
        "output": ["hostid"],
        "selectTags": ["tag", "value"],
        "tags": [
            {
                "tag": "Contract",
            }
        ]
    }

    response = zabbix_api_request({'jsonrpc': '2.0', 'method': method, 'params': params, 'auth': auth_token, 'id': 1})

    if 'result' in response:
        host_ids = [host_data["hostid"] for host_data in response['result'] if 'Contract' in [tag['tag'] for tag in host_data['tags']]]
        print(host_ids)
        return host_ids
    else:
        raise ValueError("Unexpected response from Zabbix API. 'result' field not found.")


def get_host_tags(host_id):
    method = 'host.get'
    params = {
        'output': 'extend',
        'selectTags': ['tag', 'value'],
        'hostids': host_id
    }
    response = zabbix_api_request({'jsonrpc': '2.0', 'method': method, 'params': params, 'auth': auth_token, 'id': 1})

    tags = {}
    for tag_data in response['result']:
        for tag in tag_data['tags']:
            tags[tag['tag']] = tag['value']

    return tags

def get_host_inventory(host_id):
    method = 'host.get'
    params = {
        'output': ['hostid'],
        'selectInventory': ['contract_number','poc_1_name', 'poc_1_email', 'poc_1_cell', 'poc_1_screen', 'poc_1_notes', 'poc_2_name', 'poc_2_screen', 'site_address_a', 'site_address_b', 'site_address_c', 'site_city', 'site_state', 'site_country', 'site_zip' ],  # Use 'extend' to get all inventory fields
        'hostids': host_id
    }

    response = zabbix_api_request({'jsonrpc': '2.0', 'method': method, 'params': params, 'auth': auth_token, 'id': 1})

    if 'result' in response and len(response['result']) > 0:
        inventory = response['result'][0]['inventory']
        return inventory
    else:
        raise ValueError("Unexpected response from Zabbix API. 'result' field not found or empty.")


def get_csv_row(contract,group):
    try:
        with open('inventory-job.csv', 'r') as csv_file:
            reader = csv.reader(csv_file)
            for row in reader:
                if row[0] == contract and row[1] == group:
                    return row

    except FileNotFoundError:
        raise FileNotFoundError("CSV file not found")

    return None


def compile_inventory(host_id):
    tags = get_host_tags(host_id)
    contract = tags.get('Contract')
    group = tags.get('Group')

    if contract:
        row = get_csv_row(group,contract)
        if not row:
            raise ValueError("No match found in the CSV file for the 'Contract' tag")

        current_inventory = get_host_inventory(host_id)

        # Map the CSV row to the inventory fields
        csv_inventory = {
            "contract_number": row[1],
            "poc_1_name": row[2],
            "poc_1_email": row[3],
            "poc_1_cell": row[4],
            "poc_1_screen": row[5],
            "poc_1_notes": row[6],
            "poc_2_name": row[7],
            "poc_2_screen": row[8],
            "site_address_a": row[9],
            "site_address_b": row[10],
            "site_address_c": row[11],
            "site_city": row[12],
            "site_state": row[13],
            "site_country": row[14],
            "site_zip": row[15]
        }

        # Check if the current inventory matches the CSV inventory
        if current_inventory == csv_inventory:
            print(f"Skipping host ID {host_id} as inventory values match the CSV")
            return

        # If inventory doesn't match, update it
        update_host_inventory(
            host_id,
            csv_inventory["contract_number"],
            csv_inventory["poc_1_name"],
            csv_inventory["poc_1_email"],
            csv_inventory["poc_1_cell"],
            csv_inventory["poc_1_screen"],
            csv_inventory["poc_1_notes"],
            csv_inventory["poc_2_name"],
            csv_inventory["poc_2_screen"],
            csv_inventory["site_address_a"],
            csv_inventory["site_address_b"],
            csv_inventory["site_address_c"],
            csv_inventory["site_city"],
            csv_inventory["site_state"],
            csv_inventory["site_country"],
            csv_inventory["site_zip"]
        )
    else:
        raise ValueError("The 'Contract' tag is not present for the specified host")



def update_host_inventory( 
    host_id,
    contract_number,
    primary_poc_name,
    primary_poc_email,
    primary_poc_cell,
    primary_poc_screen_name,
    primary_poc_notes,
    secondary_poc_name,
    secondary_poc_screen_name,
    site_address_a,
    site_address_b,
    site_address_c,
    site_city,
    site_state,
    site_country,
    site_zip  
):
    data = {
        "jsonrpc": "2.0",
        "method": "host.update",
        "params": {
            "hostid": host_id,
            "inventory_mode": 1,
            "inventory": {
                "contract_number": contract_number,
                "poc_1_name": primary_poc_name,
                "poc_1_email": primary_poc_email,
                "poc_1_cell": primary_poc_cell,
                "poc_1_screen": primary_poc_screen_name,
                "poc_1_notes": primary_poc_notes,
                "poc_2_name": secondary_poc_name,
                "poc_2_screen": secondary_poc_screen_name,
                "site_address_a": site_address_a,
                "site_address_b": site_address_b,
                "site_address_c": site_address_c,
                "site_city": site_city,
                "site_state": site_state,
                "site_country": site_country,
                "site_zip": site_zip
            }
        },
        "auth": auth_token,
        "id": 1
    }
    response = zabbix_api_request(data)
    print(f"Updated inventory of host ID: {host_id}")

def compile_inventory_for_all_hosts():
    host_ids = get_all_host_ids()
    for host_id in host_ids:
        try:
            compile_inventory(host_id)
        except ValueError as e:
            print(f"Skipping host ID {host_id} due to error: {str(e)}")



if zabbix_api_request(auth_payload, test_credentials=True):
    auth_token = zabbix_api_request(auth_payload)['result']
    print("Valid Zabbix credentials.")
    compile_inventory_for_all_hosts()
else:
    raise Exception("Invalid Zabbix credentials. Please verify your username and password.")

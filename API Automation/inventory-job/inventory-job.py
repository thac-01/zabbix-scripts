import requests
import csv
import urllib3

# Disable SSL warnings
urllib3.disable_warnings()

# Define the URL and credentials for the Zabbix API
url = "https://ip-address/api_jsonrpc.php"
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

# Function to make Zabbix API request
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
        
        # Attivare per fare Debug
        print (response.json())

        if test_credentials:
            if "result" in response.json() and "error" not in response.json():
                return True
            return False
        
        return response.json()
    except requests.exceptions.RequestException as e:
        raise Exception(f"Zabbix API request failed: {str(e)}")


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


def get_csv_row(group, customer):
    try:
        with open('inventory.csv', 'r') as csv_file:
            reader = csv.reader(csv_file)
            for row in reader:
                if row[0] == group and row[1] == customer:
                    return row

    except FileNotFoundError:
        raise FileNotFoundError("CSV file not found")

    return None


def compile_inventory(host_id):
    tags = get_host_tags(host_id)
    group = tags.get('Group')
    customer = tags.get('Customer')

    if group and customer:
        row = get_csv_row(group, customer)
        if not row:
            raise ValueError("No match found in the CSV file for 'Group' and 'Customer' tags")

        primary_poc_name = row[2]
        primary_poc_email = row[3]
        primary_poc_cell = row[4]
        primary_poc_screen_name = row[5]
        primary_poc_notes = row[6]
        secondary_poc_name = row[7]
        secondary_poc_screen_name = row[8]

        update_host_inventory(
            host_id,
            primary_poc_name,
            primary_poc_email,
            primary_poc_cell,
            primary_poc_screen_name,
            primary_poc_notes,
            secondary_poc_name,
            secondary_poc_screen_name
        )
    else:
        raise ValueError("The 'Group' and/or 'Customer' tags are not present for the specified host")


def update_host_inventory( 
    host_id,
    primary_poc_name,
    primary_poc_email,
    primary_poc_cell,
    primary_poc_screen_name,
    primary_poc_notes,
    secondary_poc_name,
    secondary_poc_screen_name
):
    data = {
        "jsonrpc": "2.0",
        "method": "host.update",
        "params": {
            "hostid": host_id,
            "inventory_mode": 1,
            "inventory": {
                "poc_1_name": primary_poc_name,
                "poc_1_email": primary_poc_email,
                "poc_1_cell": primary_poc_cell,
                "poc_1_screen": primary_poc_screen_name,
                "poc_1_notes": primary_poc_notes,
                "poc_2_name": secondary_poc_name,
                "poc_2_screen": secondary_poc_screen_name
            }
        },
        "auth": auth_token,
        "id": 1
    }
    response = zabbix_api_request(data)


def get_all_host_ids():
    method = 'host.get'
    params = {
        "output": ["hostid"],
        "selectGroups": "extend",
        "selectTags": "extend"
    }

    response = zabbix_api_request({'jsonrpc': '2.0', 'method': method, 'params': params, 'auth': auth_token, 'id': 1})

    if 'result' in response:
        host_ids = [host_data["hostid"] for host_data in response['result'] if 'Group' in [tag['tag'] for tag in host_data['tags']] and 'Customer' in [tag['tag'] for tag in host_data['tags']]]
        print (host_ids)
        return host_ids
    else:
        raise ValueError("Unexpected response from Zabbix API. 'result' field not found.")



def compile_inventory_for_all_hosts():
    host_ids = get_all_host_ids()
    for host_id in host_ids:
        try:
            compile_inventory(host_id)
        except ValueError as e:
            print(f"Skipping host ID {host_id} due to error: {str(e)}")


auth_response = zabbix_api_request(auth_payload)
auth_token = auth_response['result']

if zabbix_api_request(auth_payload, test_credentials=True):
    print("Valid Zabbix credentials.")
    compile_inventory_for_all_hosts()
else:
    raise Exception("Invalid Zabbix credentials. Please verify your username and password.")

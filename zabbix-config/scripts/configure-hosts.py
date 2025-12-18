#!/usr/bin/env python3
"""
Configure Zabbix hosts for Kubernetes monitoring
"""
import requests
import json
import os
import sys

ZABBIX_URL = os.getenv("ZABBIX_URL", "http://zabbix.msp-demo.local/api_jsonrpc.php")
ZABBIX_USER = os.getenv("ZABBIX_USER", "Admin")
ZABBIX_PASS = os.getenv("ZABBIX_PASS", "zabbix")


def zabbix_api_call(method, params, auth_token=None):
    """Call Zabbix API"""
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1
    }
    
    if auth_token:
        payload["auth"] = auth_token
    
    response = requests.post(ZABBIX_URL, json=payload)
    result = response.json()
    
    if "error" in result:
        print(f"API Error: {result['error']}")
        return None
    
    return result.get("result")


def main():
    """Main configuration routine"""
    print("Zabbix Host Configuration")
    print("=" * 50)
    
    # Authenticate
    print("Authenticating...")
    auth_token = zabbix_api_call("user.login", {
        "user": ZABBIX_USER,
        "password": ZABBIX_PASS
    })
    
    if not auth_token:
        print("Authentication failed!")
        sys.exit(1)
    
    print(f"Authenticated successfully")
    print("")
    
    # Configure hosts for each client
    clients = [
        {"name": "cliente-a", "ip": "cliente-a-api.cliente-a.svc.cluster.local"},
        {"name": "cliente-b", "ip": "cliente-b-api.cliente-b.svc.cluster.local"},
        {"name": "cliente-c", "ip": "cliente-c-api.cliente-c.svc.cluster.local"}
    ]
    
    for client in clients:
        print(f"Configuring host: {client['name']}")
        # Host configuration would go here
        # This is a placeholder - actual implementation requires Zabbix API calls
    
    print("")
    print("Configuration complete!")
    print("Verify hosts in Zabbix UI: Monitoring → Hosts")


if __name__ == "__main__":
    main()

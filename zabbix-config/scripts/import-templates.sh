#!/bin/bash
#
# Import Zabbix templates
#

set -e

echo "Importing Zabbix templates..."

ZABBIX_URL=${ZABBIX_URL:-"http://zabbix.msp-demo.local"}
ZABBIX_USER=${ZABBIX_USER:-"Admin"}
ZABBIX_PASS=${ZABBIX_PASS:-"zabbix"}

echo "Zabbix URL: $ZABBIX_URL"
echo ""

# This script would use Zabbix API to import templates
# For now, templates need to be imported manually via UI

echo "Templates to import:"
echo "  - msp-cliente-a.yaml (E-commerce, SLA 99%)"
echo "  - msp-cliente-b.yaml (Fintech, SLA 99.99%)"
echo "  - msp-cliente-c.yaml (SaaS, SLA 99.5%)"
echo ""
echo "Import via Zabbix UI:"
echo "  1. Login to $ZABBIX_URL"
echo "  2. Configuration → Templates → Import"
echo "  3. Upload each YAML file from zabbix-config/templates/"
echo ""
echo "After import, configure webhook actions pointing to:"
echo "  http://webhook-handler.monitoring.svc.cluster.local:8080/trigger"

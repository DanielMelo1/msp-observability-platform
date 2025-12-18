#!/bin/bash
#
# Load test script using kubectl
#

CLIENT=${1:-cliente-a}

echo "Starting load test on $CLIENT..."
echo "Press Ctrl+C to stop"

kubectl run load-generator-$CLIENT --image=busybox --restart=Never -n $CLIENT \
  -- /bin/sh -c "while true; do wget -q -O- http://${CLIENT}-api:8000/api/items; done"

echo ""
echo "Load generator running. Watch scaling with:"
echo "  kubectl get hpa -n $CLIENT --watch"
echo ""
echo "To stop:"
echo "  kubectl delete pod load-generator-$CLIENT -n $CLIENT"

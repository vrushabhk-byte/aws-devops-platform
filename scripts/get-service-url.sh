#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-production}"
service="${2:-flask-api}"

for _ in $(seq 1 30); do
  hostname="$(kubectl get service "$service" -n "$namespace" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  ip="$(kubectl get service "$service" -n "$namespace" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"

  if [[ -n "$hostname" ]]; then
    echo "http://${hostname}"
    exit 0
  elif [[ -n "$ip" ]]; then
    echo "http://${ip}"
    exit 0
  fi

  sleep 10
done

echo "LoadBalancer address is not ready yet. Check: kubectl get service ${service} -n ${namespace}"
exit 1

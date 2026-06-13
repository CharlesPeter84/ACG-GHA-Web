#!/usr/bin/env bash
set -euo pipefail
set -x

export ANSIBLE_HOST_KEY_CHECKING=${ANSIBLE_HOST_KEY_CHECKING:-False}

mkdir -p /tmp/ansible
printf '%s\n' "$SSH_PRIVATE_KEY" > /tmp/ansible/ssh_key
chmod 600 /tmp/ansible/ssh_key

# get instance IP via terraform output using jq or grep fallback
TERRAFORM_OUTPUT_JSON=${TERRAFORM_OUTPUT_JSON:-terraform_output.json}
IP=""
if [ ! -f "$TERRAFORM_OUTPUT_JSON" ]; then
  echo "Error: Terraform JSON output file is missing: $TERRAFORM_OUTPUT_JSON"
  echo "Ensure the workflow generates the file before running this script."
  exit 1
fi

# dump raw terraform output for debugging (masked later)
echo "--- Terraform raw JSON output ---"
cat "$TERRAFORM_OUTPUT_JSON" || true

# validate that the JSON output file contains only JSON and no surrounding text
if ! command -v jq >/dev/null 2>&1; then
  echo 'Error: jq is required to validate terraform JSON output.'
  exit 1
fi
if ! jq -e . /tmp/terraform_output.json >/dev/null 2>&1; then
  echo 'Error: terraform JSON output file is not pure JSON.'
  echo '--- Terraform raw JSON output  ---'
  cat /tmp/terraform_output.json || true
  echo '--- Terraform raw JSON output Ends---'
  exit 1
fi

echo '--- Terraform parsed JSON output ---'
jq . /tmp/terraform_output.json || true

if command -v jq >/dev/null 2>&1; then
  IP=$(jq -r '.web_instance_public_ip.value // .web_instance_public_ip // ""' "$TERRAFORM_OUTPUT_JSON" 2>/dev/null || true)
  IP=$(printf '%s' "$IP" | grep -Eo '^[0-9]+(\.[0-9]+){3}$' || true)
fi
if [ -z "$IP" ]; then
  echo "Error: terraform output 'web_instance_public_ip' is empty or missing in $TERRAFORM_OUTPUT_JSON."
  echo "Ensure the workflow generated the JSON output before running this script."
  jq . "$TERRAFORM_OUTPUT_JSON" || true
  exit 1
fi
if ! printf '%s' "$IP" | grep -Eo '^[0-9]+(\.[0-9]+){3}$' >/dev/null; then
  MASKED_IP=$(printf '%s' "$IP" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.xxx/')
  echo "Error: terraform output did not return a valid IPv4 address. Masked value: '$MASKED_IP'"
  terraform -chdir=terraform output || true
  exit 1
fi

printf "[webservers]\nec2 ansible_host=%s ansible_user=ec2-user ansible_private_key_file=/tmp/ansible/ssh_key\n" "$IP" > /tmp/ansible/inventory.ini
ansible-playbook -i /tmp/ansible/inventory.ini ansible/playbook.yml -vvv

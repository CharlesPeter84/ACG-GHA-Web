#!/usr/bin/env bash
set -euo pipefail
set -x

export ANSIBLE_HOST_KEY_CHECKING=${ANSIBLE_HOST_KEY_CHECKING:-False}

mkdir -p /tmp/ansible
printf '%s\n' "$SSH_PRIVATE_KEY" > /tmp/ansible/ssh_key
chmod 600 /tmp/ansible/ssh_key

# get instance IP via terraform output using jq or grep fallback
IP=""
# dump raw terraform output for debugging (masked later)
echo "--- Terraform raw JSON output ---"
terraform -chdir=terraform output -json > /tmp/terraform_output.json 2>&1 || true
cat /tmp/terraform_output.json || true

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
  IP=$(jq -r '.web_instance_public_ip.value // .web_instance_public_ip // ""' /tmp/terraform_output.json 2>/dev/null || true)
  IP=$(printf '%s' "$IP" | grep -Eo '^[0-9]+(\.[0-9]+){3}$' || true)
fi
if [ -z "$IP" ]; then
  # fallback to raw terraform output (non-json)
  terraform -chdir=terraform output > /tmp/terraform_output_raw.txt 2>&1 || true
  echo "--- Terraform raw text output ---"
  cat /tmp/terraform_output_raw.txt || true
  IP=$(grep -Eo '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)' /tmp/terraform_output_raw.txt | head -n1 || true)
fi

if [ -z "$IP" ]; then
  echo "Error: terraform output 'web_instance_public_ip' is empty. Ensure Terraform applied and output exists."
  terraform -chdir=terraform output || true
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

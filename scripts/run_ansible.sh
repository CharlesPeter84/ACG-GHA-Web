#!/usr/bin/env bash
set -euo pipefail

export ANSIBLE_HOST_KEY_CHECKING=${ANSIBLE_HOST_KEY_CHECKING:-False}

mkdir -p /tmp/ansible
printf '%s\n' "$SSH_PRIVATE_KEY" > /tmp/ansible/ssh_key
chmod 600 /tmp/ansible/ssh_key

TERRAFORM_OUTPUT_JSON=${TERRAFORM_OUTPUT_JSON:-terraform_output.json}
if [ ! -f "$TERRAFORM_OUTPUT_JSON" ]; then
  echo "Error: Terraform JSON output file is missing: $TERRAFORM_OUTPUT_JSON"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo 'Error: jq is required to parse terraform JSON output.'
  exit 1
fi

IP=$(jq -r '.web_instance_public_ip.value // .web_instance_public_ip // empty' "$TERRAFORM_OUTPUT_JSON")
if [ -z "$IP" ]; then
  echo "Error: terraform output 'web_instance_public_ip' is missing or empty in $TERRAFORM_OUTPUT_JSON."
  jq . "$TERRAFORM_OUTPUT_JSON" || true
  exit 1
fi

if ! printf '%s' "$IP" | grep -Eq '^[0-9]+(\.[0-9]+){3}$'; then
  echo "Error: parsed Terraform IP is not a valid IPv4 address: $IP"
  exit 1
fi

cat > /tmp/ansible/inventory.ini <<EOF
[webservers]
ec2 ansible_host=$IP ansible_user=ec2-user ansible_private_key_file=/tmp/ansible/ssh_key
EOF

ansible-playbook -i /tmp/ansible/inventory.ini ansible/playbook.yml

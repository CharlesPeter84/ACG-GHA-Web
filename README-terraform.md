# Terraform + GitHub Actions EC2 deploy

Files added:

- terraform/main.tf
- terraform/variables.tf
- terraform/backend.tf
- terraform/outputs.tf
- ansible/playbook.yml
- ansible/roles/nginx/tasks/main.yml
- ansible/roles/nginx/handlers/main.yml
- ansible/roles/nginx/templates/default.conf.j2
- web/index.html
- web/about.html
- web/style.css
- .github/workflows/deploy-ec2.yml

Setup steps:

1. In your GitHub repository settings -> Secrets -> Actions add these secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_REGION` (e.g., `us-east-1`)
   - `TF_S3_BUCKET` (S3 bucket to store Terraform state)
   - `TF_DYNAMODB_TABLE` (DynamoDB table name for state locking)
   - `SSH_PRIVATE_KEY` (private key for Ansible to connect to the EC2 instance)

2. SSH access setup — choose one:

   **Option A: Import a new SSH public key**
   
   Generate locally:
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/terraform-key -N ""
   ```
   
   Add the public key to GitHub secrets as `TF_VAR_ssh_public_key`:
   ```bash
   cat ~/.ssh/terraform-key.pub
   ```
   Copy the output and add it to your repository secrets.

   Then add the corresponding private key to GitHub secrets as `SSH_PRIVATE_KEY`:
   ```bash
   cat ~/.ssh/terraform-key
   ```

   **Option B: Use an existing EC2 Key Pair**
   
   Create a repository secret named `TF_VAR_ssh_key_name` with the existing key pair name (it must already exist in AWS), and add the matching private key as `SSH_PRIVATE_KEY`.

3. Create the S3 bucket and DynamoDB table (locking) before running init. Example AWS CLI commands:

```bash
aws s3api create-bucket --bucket my-terraform-state-bucket --region us-east-1 --create-bucket-configuration LocationConstraint=us-east-1
aws dynamodb create-table --table-name my-terraform-locks --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
```

4. Verify the DynamoDB lock table schema before initializing Terraform:

```bash
aws dynamodb describe-table --table-name my-terraform-locks --query 'Table.KeySchema'
```

It must return a single key schema entry with `AttributeName` set to `LockID` and `KeyType` set to `HASH`.

5. Locally, initialize Terraform with backend-config values:

```bash
cd terraform
terraform init -backend-config="bucket=my-terraform-state-bucket" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=my-terraform-locks"
```

6. Commit and push to `main`. The workflow will use the repository secrets `TF_S3_BUCKET`, `TF_DYNAMODB_TABLE`, and `SSH_PRIVATE_KEY` to configure the backend and run Ansible if needed. The state object key is fixed to `state/terraform.tfstate`.

7. Ansible behavior:
   - The workflow runs Ansible when `ansible/**`, `web/**`, or `terraform/**` changes.
   - Website files in `web/` are copied to `/var/www/html` only when their contents change.

8. (SSH access) After deployment, retrieve the EC2 public IP from Terraform output or AWS Console, then connect:

```bash
ssh -i ~/.ssh/terraform-key ec2-user@<instance-ip>
```

Notes:
- The workflow runs `terraform apply -auto-approve`. For production, consider requiring manual approval.
- The backend is configured during `terraform init`; the repository does not hardcode bucket names.
- SSH public keys are imported via `TF_VAR_ssh_public_key` and the private key is provided as `SSH_PRIVATE_KEY` for Ansible.

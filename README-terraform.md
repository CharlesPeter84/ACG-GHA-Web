# Terraform + GitHub Actions EC2 deploy

Files added:

- terraform/main.tf
- terraform/variables.tf
- terraform/backend.tf
- .github/workflows/deploy-ec2.yml

Setup steps:

1. In your GitHub repository settings -> Secrets -> Actions add these secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_REGION` (e.g., `us-east-1`)
    - `TF_S3_BUCKET` (S3 bucket to store Terraform state)
    - `TF_DYNAMODB_TABLE` (DynamoDB table name for state locking)

2. (Optional) SSH access setup — choose one:

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
   
   **Option B: Use an existing EC2 Key Pair**
   
   Create a repository secret named `TF_VAR_ssh_key_name` with the existing key pair name (it must already exist in AWS).

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

6. Commit and push to `main`. The workflow will use the repository secrets `TF_S3_BUCKET` and `TF_DYNAMODB_TABLE` to configure the backend during `terraform init`. The state object key is fixed to `state/terraform.tfstate`.

7. (SSH access) Once the EC2 instance is deployed with an imported public key, get the instance IP from AWS Console, then connect:

```bash
ssh -i ~/.ssh/terraform-key ec2-user@<instance-ip>
```

Notes:
- The workflow runs `terraform apply -auto-approve`. For production, consider requiring manual approval.
- The backend is configured during `terraform init`; the repository does not hardcode bucket names.
- SSH public keys are imported as variables via `TF_VAR_ssh_public_key` secret. The key name is auto-generated with a timestamp.

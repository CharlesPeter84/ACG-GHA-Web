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
+  - `TF_S3_BUCKET` (S3 bucket to store Terraform state)
+  - `TF_STATE_KEY` (object key, e.g. `state/terraform.tfstate`)
+  - `TF_DYNAMODB_TABLE` (DynamoDB table name for state locking)

2. (Optional) If you want SSH access, create or use an existing EC2 Key Pair name and set it by creating a repository secret named `TF_VAR_ssh_key_name` or update `terraform/variables.tf`.

3. Create the S3 bucket and DynamoDB table (locking) before running init. Example AWS CLI commands:

```bash
aws s3api create-bucket --bucket my-terraform-state-bucket --region us-east-1 --create-bucket-configuration LocationConstraint=us-east-1
aws dynamodb create-table --table-name my-terraform-locks --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
```

4. Locally, initialize Terraform with backend-config values:

```bash
cd terraform
terraform init -backend-config="bucket=my-terraform-state-bucket" \
  -backend-config="key=state/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=my-terraform-locks"
```

5. Commit and push to `main`. The workflow will use the repository secrets `TF_S3_BUCKET`, `TF_STATE_KEY`, and `TF_DYNAMODB_TABLE` to configure the backend during `terraform init`.

Notes:
- The workflow runs `terraform apply -auto-approve`. For production, consider requiring manual approval.
- The backend is configured during `terraform init`; the repository does not hardcode bucket names.

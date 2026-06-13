# Terraform + GitHub Actions EC2 deploy

Files added:

- terraform/main.tf
- terraform/variables.tf
- .github/workflows/deploy-ec2.yml

Setup steps:

1. In your GitHub repository settings -> Secrets -> Actions add these secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_REGION` (e.g., `us-east-1`)

2. (Optional) If you want SSH access, create or use an existing EC2 Key Pair name and set it by creating a repository secret named `TF_VAR_ssh_key_name` or update `terraform/variables.tf`.

3. Commit and push to `main`. The workflow runs on pushes to `main` and will `terraform init`, `plan`, and `apply`.

Notes:
- The workflow runs `terraform apply -auto-approve`. For production, consider requiring manual approval.
- Terraform state is stored locally in the runner workspace; for team/project use configure a remote backend (S3 + DynamoDB).

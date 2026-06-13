terraform {
  backend "s3" {
    # State object key is fixed to the repository vault path
    key = "state/terraform.tfstate"
  }
}

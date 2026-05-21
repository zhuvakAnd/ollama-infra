provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

terraform {
  backend "s3" {
    bucket = "terraform-state-058264468006-eu-north-1-an"
    key    = "ci-cd-state/terraform.tfstate"
    region = "eu-north-1"

    # Optional but recommended
    encrypt = true
  }
}

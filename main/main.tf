provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "tfstate-542776677488-eu-north-1-an"
    key    = "main-state/terraform.tfstate"
    region = "eu-north-1"

    encrypt = true
  }
}
#history

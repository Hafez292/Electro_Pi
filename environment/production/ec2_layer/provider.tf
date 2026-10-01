terraform {
  required_version = ">= 1.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"
    }
  }

  backend "s3" {
    bucket = "7ader-terraform"
    key    = "ec2/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "7ader-terraform"
    key    = "vpc/terraform.tfstate"
    region = "us-east-1"
  }
}
 
data "terraform_remote_state" "permission" {
  backend = "s3"

  config = {
    bucket = "7ader-terraform"
    key    = "permission/terraform.tfstate"
    region = "us-east-1"
  }
}
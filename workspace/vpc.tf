module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.0.1"

  name = "main-vpc"
  cidr = "10.56.0.0/16"

  # https://www.davidc.net/sites/default/subnets/subnets.html?network=10.56.0.0&mask=16&division=25.f9c4e00
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.56.0.0/21", "10.56.8.0/21", "10.56.16.0/21"]
  public_subnets  = ["10.56.24.0/21", "10.56.32.0/21", "10.56.40.0/21"]
  intra_subnets   = ["10.56.48.0/21", "10.56.56.0/21", "10.56.64.0/21"]

  enable_nat_gateway = true
  enable_vpn_gateway = false

  tags = {
    Terraform   = "true"
    Environment = "poc"
  }
}
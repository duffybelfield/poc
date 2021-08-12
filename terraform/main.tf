terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Centralising terraform state on a seperate managed s3 bucket that uses a global KMS key for encryption

terraform {
  backend "s3" {
    bucket         = "tfstate-eu-central-1-poc"
    key            = "infrastructure.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "tfstate-eu-central-1-poc"
  }
}

provider "aws" {
  region = local.region
}

# Setting some default values

locals {
  name   = "poc-didomi"
  region = "eu-west-1"
  tags = {
    Owner       = "user"
    Environment = "poc"
  }
}

data "aws_region" "current" {}


# https://github.com/terraform-aws-modules/terraform-aws-rds/tree/master/examples/complete-postgres
# https://github.com/terraform-aws-modules/terraform-aws-vpc/blob/v3.3.0/examples/complete-vpc/main.tf

# creating the VPC without only private subnets

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2"

  name = local.name
  cidr = "20.10.0.0/16"

  azs              = ["${local.region}a", "${local.region}b", "${local.region}c"]
  database_subnets = ["20.10.21.0/24", "20.10.22.0/24", "20.10.23.0/24"]

  create_database_subnet_group = false

  # Default security group - ingress/egress rules cleared to deny all
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # VPC Flow Logs (Cloudwatch log group and IAM role will be created)
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  tags = local.tags
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier = local.name

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine               = "postgres"
  engine_version       = "11.10"
  family               = "postgres11" # DB parameter group
  major_engine_version = "11"         # DB option group
  instance_class       = "db.t3.xlarge"


  allocated_storage     = 20
  max_allocated_storage = 100
  storage_encrypted     = false

  name     = "completePostgresql"
  username = "complete_postgresql"
  password = "YourPwdShouldBeLongAndSecure!"
  port     = 5432

  # Enabling MultiAZ for scalability and redundancy
  multi_az               = true
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_group.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Setting 30 days of back up redundancy for those "oops" moments :)
  backup_retention_period = 30
  skip_final_snapshot     = false
  deletion_protection     = true

  # Performance insights are great for validating good code / indexes on a new deployment, metrics / alarms etc.
  performance_insights_enabled          = true
  performance_insights_retention_period = 14
  create_monitoring_role                = true
  monitoring_interval                   = 60

  # https://postgreshelp.com/postgresql-autovacuum/
  # The purpose of autovacuum is to automate the execution of VACUUM and ANALYZE commands. 
  # When enabled, autovacuum checks for tables that have had a large number of inserted, updated or deleted tuples 
  # and then vacuum or analyze the table based on the threshold.

  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]

}

# Default security group for Postgres RDS with ingress of 5432 (not using a source security group)

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4"

  name        = local.name
  description = "PostgreSQL security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  tags = local.tags
}

# Make sure we grab our terraform state / KMS key within our private VPC and not over the public endpoints

module "endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.security_group.security_group_id]

  endpoints = {
    s3 = {
      # interface endpoint
      service = "s3"
      tags    = { Name = "s3-vpc-endpoint" }
    },
    kms = {
      service             = "kms"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
  }

  tags = local.tags
}


# Didomi POC

__Problem Statement:__

The Preference Management Platform (PMP) team has decided on their architecture. They want to create an API using the following technologies:

* an API Gateway
* a Postgresql Database
* a single lambda deployed with serverless. The lambda needs to make requests to a 3rd party public API. The Lambda also needs to fetch large amounts of data from S3.

The PMP team uses Gitlab runners for CI/CD and needs to be able to deploy their changes using the pipeline. Another problem the team is thinking about is how they can run their migrations inside the pipeline.

## Cloudformation
* S3 bucket encrypted to managed terraform state
* KMS key with relevant permissions to encrypt objects within the state bucket

## Terraform

* A VPC with private subnets (also enabling VPC endpoints for adding network security)
* An RDS database that can handle at scale concurrency for our deployed Lambda
    * T3 CPU Credits
        Amazon RDS T3 DB instances run in Unlimited mode, which means that you will be charged if your average CPU utilization over a rolling 24-hour period exceeds the baseline of the instance. CPU Credits are charged at $0.075 per vCPU-Hour. The CPU Credit pricing is the same for all T3 instance sizes across all regions and is not covered by Reserved Instances.
    * With performance insights enabled we can alarm on DBLoad, DBLoadCPU and DBLoadNonCPU

## Serverless

* An IAM user for Gitlab to run the deployment for the lambda in the pipeline
* Policies for the Gitlab user with the minimal required permissions to run the deployment
* An API Gateway that will handle the incoming requests
* A lambda that would connect to the RDS, do some processing, and return a response
* The configuration required to make requests go through a custom domain (Route53, ACM, etc.)

In addition:
* Centralise serverless deployments to one bucket
* Used Customer Managed Policies that attach to IAM User

## How to deploy?
* Deploy cloudformation via aws cli or console
    1. kms-key.yml
    1. terraform-state.yml
* Deploy terraform
* Deploy serverless with the additional requirements for serverless domain manager to create certificates / domains etc.

### References
* [Terraform DB Module](https://github.com/terraform-aws-modules/terraform-aws-rds/tree/master/examples/complete-postgres)
* [Serverless.yml](https://www.serverless.com/framework/docs/providers/aws/guide/serverless.yml/)
* [Serverless Domain Manager](https://www.serverless.com/plugins/serverless-domain-manager)
* [Serverless Deployment Bucket](https://www.npmjs.com/package/serverless-deployment-bucket)
* [Set alarms on Performance Insights metrics using Amazon CloudWatch](https://aws.amazon.com/blogs/database/set-alarms-on-performance-insights-metrics-using-amazon-cloudwatch/)
* [Widdix AWS CF Templates](https://github.com/widdix/aws-cf-templates)

I've used Customer Managed Policies so that I can re-use them for other principle entities (if required)

![Example of Customer Managed Policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/images/policies-customer-managed-policies.diagram.png)
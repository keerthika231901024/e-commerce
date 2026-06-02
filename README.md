# Keerthi E-Commerce (Serverless AWS Project)

## Project Overview
Keerthi E-Commerce is a serverless web application built on AWS for managing products, cart, orders, and user auth. The frontend now includes order-history popularity recommendations, using past orders to surface the most frequently purchased products.

## Table of Contents
- [Architecture](#architecture)
- [Key Features](#key-features)
- [Technology Stack](#technology-stack)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [How to Run](#how-to-run)
- [API Endpoints](#api-endpoints)
- [Monitoring and Observability](#monitoring-and-observability)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)
- [Future Improvements](#future-improvements)
- [License](#license)

## Architecture
- **Frontend:** Hosted on **Amazon S3** and delivered via **Amazon CloudFront**
- **Backend APIs:** Built with **Amazon API Gateway** and **AWS Lambda**
- **Database:** **Amazon DynamoDB** for product and cart data storage
- **Infrastructure as Code:** Provisioned using **Terraform**
- **Monitoring & Tracing:** Enabled with **Amazon CloudWatch** and **AWS X-Ray**

### Layered Service Architecture

```text
+-------------------------------------------------------------+
|                       API Gateway                           |
|              (Routes requests to backend services)          |
+-------------------------------------------------------------+
                 |                    |                    |
                 v                    v                    v
+-------------------------+ +-------------------------+ +-------------------------+
| Product Service         | | Cart Service            | | Order Service          |
| (AWS Lambda)            | | (AWS Lambda)            | | (AWS Lambda)            |
+-------------------------+ +-------------------------+ +-------------------------+
                 |                    |                    |
                 v                    v                    v
+-------------------------+ +-------------------------+ +-------------------------+
| DynamoDB Product Table  | | DynamoDB Cart Table     | | DynamoDB Order Table   |
+-------------------------+ +-------------------------+ +-------------------------+
```

### Request Flow
1. User accesses the web app through CloudFront.
2. CloudFront serves static frontend assets from S3.
3. Frontend sends API requests to API Gateway.
4. API Gateway invokes Lambda handlers.
5. Lambda functions read/write data in DynamoDB.
6. Logs and traces are captured in CloudWatch and X-Ray.

## Key Features
- Add, view, and delete products
- Add to cart, view cart, and delete cart items
- Order-history popularity recommendations on the homepage
- User registration and login backed by DynamoDB
- Fully serverless architecture (no server management)
- Logging and monitoring enabled for backend services

## Technology Stack
- AWS Lambda
- Amazon API Gateway
- Amazon DynamoDB
- Amazon S3
- Amazon CloudFront
- Terraform
- Amazon CloudWatch
- AWS X-Ray
- HTML, CSS, JavaScript

## Prerequisites
- AWS account with permissions for Lambda, API Gateway, DynamoDB, S3, CloudFront, CloudWatch, X-Ray, and IAM
- Terraform v1.4+ installed locally
- AWS CLI v2 configured (`aws configure`)
- Python 3.9+ (for Lambda runtime compatibility and local testing)
- A globally unique S3 bucket name for frontend hosting

## Project Structure
```text
keerthi_frontend/
├── README.md
├── out.json
├── payload.json
├── terraform.tfstate
├── terraform.tfstate.backup
├── backend/
│   ├── auth/
│   │   └── lambda_function.py
│   ├── cart/
│   │   └── cart_fun.py
│   ├── order/
│   │   └── lambda_function.py
│   └── product/
│       └── lambda_function.py
├── frontend/
│   ├── index.html
│   ├── cart.html
│   ├── login.html
│   ├── orders.html
│   ├── website.test.html
│   ├── assets/
│   │   └── images/
│   ├── css/
│   │   └── style.css
│   └── js/
│       └── script.js
└── terraform/
    ├── main.tf
    ├── plan_output.txt
    ├── terraform.tfstate
    ├── terraform.tfstate.backup
    ├── tfplan
    └── variables.tf
```

## Configuration
Before deploying, update these values in Terraform and frontend files:

- AWS region
- DynamoDB table names
- S3 bucket name for static hosting
- API Gateway stage/base URL
- CloudFront distribution settings

Recommended Terraform variables:

```hcl
# variables.tf (example)
variable "aws_region" {
	type    = string
	default = "ap-south-1"
}

variable "frontend_bucket_name" {
	type = string
}

variable "project_name" {
	type    = string
	default = "keerthi-ecommerce"
}
```

## API Endpoints
| Endpoint | Methods | Description |
|----------|---------|-------------|
| `/products` | `GET`, `POST` | Fetch and add products |
| `/cart` | `GET`, `POST`, `DELETE` | Manage cart items |
| `/orders` | `GET`, `POST` | Fetch order history and place orders |
| `/auth/login` | `POST` | Validate credentials against DynamoDB |
| `/auth/logout` | `POST` | End the user session |
| `/auth/me` | `GET` | Get current authenticated user details |

### Sample API Calls

Set your API base URL:

```bash
API_BASE_URL="https://<api-id>.execute-api.<region>.amazonaws.com/<stage>"
```

Create a product:

```bash
curl -X POST "$API_BASE_URL/products" \
	-H "Content-Type: application/json" \
	-d '{
		"productId": "P1001",
		"name": "Wireless Mouse",
		"price": 899,
		"category": "electronics"
	}'
```

Get all products:

```bash
curl "$API_BASE_URL/products"
```

Add item to cart:

```bash
curl -X POST "$API_BASE_URL/cart" \
	-H "Content-Type: application/json" \
	-d '{
		"productId": "P1001",
		"quantity": 1
	}'
```

Get recent orders:

```bash
curl "$API_BASE_URL/orders"
```

## Monitoring and Observability
- **CloudWatch Logs** configured for Lambda functions and API Gateway
- **AWS X-Ray tracing** enabled for request path visibility and latency analysis

Operational checks after deployment:
- Verify API Gateway access/execution logs are enabled.
- Confirm Lambda log groups exist and receive invocation logs.
- Open X-Ray Service Map and validate end-to-end traces.
- Add CloudWatch alarms for Lambda errors, throttles, and high duration.

## How to Run
### 1. Initialize and deploy infrastructure using Terraform
```bash
terraform init
terraform plan
terraform apply
```

Optional: use a dedicated variable file for environments.

```bash
terraform apply -var-file="dev.tfvars"
```

### 2. Upload frontend to S3
```bash
aws s3 sync . s3://<your-frontend-bucket-name> --exclude "*.tfstate*" --exclude ".terraform/*"
```

### 3. Access application via CloudFront
- Open the CloudFront distribution URL from the AWS Console
- Ensure API endpoints in frontend JavaScript point to your deployed API Gateway base URL

### 4. Validate deployment
- Open the homepage and test product creation.
- Verify cart operations (add, view, delete).
- Confirm homepage recommendations update based on past orders and cart contents.
- Inspect CloudWatch logs for successful Lambda invocations.

## Security Considerations
- Apply least-privilege IAM roles for Lambda and Terraform execution.
- Restrict S3 bucket public access; use CloudFront Origin Access Control.
- Enable API Gateway request validation and throttling.
- Sanitize and validate all API inputs in Lambda handlers.
- Avoid hardcoding secrets; use AWS Systems Manager Parameter Store or AWS Secrets Manager.

## Troubleshooting
- `403 AccessDenied` on frontend: verify S3 policy/OAC configuration and CloudFront origin settings.
- API returns `500`: check Lambda CloudWatch logs and environment variables.
- CORS errors in browser: ensure API Gateway CORS headers are configured for all required methods.
- Empty data from DynamoDB: confirm table name and region in Lambda configuration.
- Terraform apply failures: validate IAM permissions and provider region configuration.

## Future Improvements
- Add route protection and authorization claims for logged-in users
- Improve UI/UX for desktop and mobile experience
- Introduce user-based cart isolation
- Add CI/CD pipeline for automated deployment
- Add infrastructure tests and policy checks (e.g., `terraform validate`, `tflint`, `checkov`)
- Introduce canary deployments for Lambda using aliases and weighted traffic

## Notes
- The Cognito module is partially implemented under `terraform/cognito`.
- Update environment-specific values (bucket names, API URLs, region, table names) before deployment.
- Use separate Terraform state/workspaces for `dev`, `staging`, and `prod`.

## License
This project is for educational and demonstration purposes.

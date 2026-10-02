# Candidate Assessment Solution Document

**Project:** Electro Pi — Three-Tier Application Assessment  
**Document type:** Editable technical compliance report  
**Assessment basis:** Repository contents in this workspace at the time this document was prepared

> **Important — evidence-based assessment:** This report distinguishes implemented items from assignment criteria that are not present in the checked-in repository. It does not claim ECS Fargate, CloudWatch alarms/log groups, RDS encryption at rest, least-privilege network rules, or an end-to-end Compose stack where the code does not implement them.

---

## 1. Executive Summary & Architecture Overview

### 1.1 Candidate implementation

The candidate has implemented an AWS-hosted three-tier application using **Terraform**, **GitHub Actions**, Docker images, **EC2**, and **Amazon RDS for PostgreSQL**. The source tree is modular: reusable Terraform modules are under `modules/`, while production layer configurations live under `environment/production/`.

**Architecture decision evidenced in code:** AWS + Terraform + GitHub Actions + EC2-based application hosts + RDS PostgreSQL. The requested **ECS Fargate** execution model is not implemented in this checkout. The app workflows build and publish images to ECR, then deploy to EC2 over SSH.

### 1.2 Three-tier request path

```text
┌──────────────────────────────┐
│ Presentation tier            │
│ Nginx static frontend :80    │
└──────────────┬───────────────┘
               │ /api/* reverse proxy
               ▼
┌──────────────────────────────┐
│ Application tier             │
│ Node.js / Express API :5000  │
└──────────────┬───────────────┘
               │ PostgreSQL query (SELECT NOW())
               ▼
┌──────────────────────────────┐
│ Data tier                    │
│ AWS RDS PostgreSQL :5432     │
└──────────────────────────────┘
```

| Tier | Implemented component | Evidence |
| --- | --- | --- |
| Presentation | Static page served by Nginx; `/api/` reverse proxy to `backend-api:5000`. | `app/frontend/index.html`, `app/frontend/nginx.conf`, `app/frontend/Dockerfile` |
| Application | Node.js/Express API with `/health` and `/api/data`; PostgreSQL client is `pg`. | `app/backend/server.js`, `app/backend/package.json` |
| Data | PostgreSQL `16.3` RDS instance configured as non-public and placed in the configured private subnets. | `modules/rds/main.tf`, `environment/production/rds_layer/main.tf` |

---

## 2. Requirement A — Infrastructure as Code (IaC) Compliance

### 2.1 IaC tool and organization

**IaC tool:** Terraform.  
**Organization:** reusable modules at repository root, composed by production environment layer directories. This is a modular approach rather than a single monolithic Terraform file.

| Requirement | Assignment example | Implemented AWS resource / status | Actual Terraform location |
| --- | --- | --- | --- |
| Networking | VPC, public subnets, private DB subnets, IGW, route tables | **Implemented:** VPC, public/private subnets, IGW, NAT Gateway, EIP, route tables, associations. | `modules/vpc/`; composition: `environment/production/vpc_layer/` |
| Compute | ECS Fargate cluster and task definition | **Not implemented:** no ECS cluster, service, task definition, or Fargate resource found. EC2 instances are provisioned instead. | `modules/ec2/`; composition: `environment/production/ec2_layer/` |
| Managed database | RDS PostgreSQL instance | **Implemented:** RDS PostgreSQL `16.3`, DB subnet group, non-public access. | `modules/rds/`; composition: `environment/production/rds_layer/` |
| Container registry | ECR repository | **Referenced, not provisioned:** GitHub workflows push to named ECR repositories; no Terraform ECR resource/module is present. | Repository configuration is in `.github/workflows/backend_pipe.yml` and `.github/workflows/frontend_pipeline.yml`; no `terraform/main.tf` exists. |
| State management | Remote Terraform state | **Implemented:** S3 backend configured per layer in `us-east-1`. | `environment/production/*_layer/provider.tf` |

### 2.2 File organization rationale

The Terraform tree separates reusable resource definitions from environment composition:

```text
modules/
├── vpc/       # VPC, subnet, gateway, and route-table resources
├── ec2/       # Reusable Ubuntu EC2 instance
└── rds/       # PostgreSQL RDS instance and DB subnet group

environment/production/
├── vpc_layer/
├── permission_layer/
├── ec2_layer/
└── rds_layer/
```

The separation allows the production layers to call reusable modules while remote-state outputs connect dependent layers. The configured S3 state bucket is `electro-terraform`; its state keys are `vpc/terraform.tfstate`, `permission/terraform.tfstate`, `ec2/terraform.tfstate`, and `rds/terraform.tfstate`.

**Why this organization:** Module boundaries encapsulate repeatable resource patterns; environment layers hold environment-specific inputs, provider/backend configuration, and module wiring. It improves reuse and makes the dependency order (VPC → permissions → EC2/RDS) visible.

### 2.3 Naming and tagging convention

The code uses a limited set of naming/tagging patterns; a universal `var.environment` tag strategy is **not** applied to all resources.

| Resource group | Observed tags / convention | Evidence |
| --- | --- | --- |
| VPC | `Name = var.tag_vpc` | `modules/vpc/main.tf` |
| Public/private subnets | `Name = each.key` | `modules/vpc/main.tf` |
| IGW and route tables | Static `Name` values such as `IGW`, `Public_Router`, `Private_Router` | `modules/vpc/main.tf` |
| EC2 | `Name = var.instance_name`, merged with optional `var.add_tag` map | `modules/ec2/main.tf`; production inputs in `environment/production/ec2_layer/terraform.tfvars` |
| RDS and DB subnet group | `Name` plus `Environment = var.environment` | `modules/rds/main.tf` |
| Security groups | Static `Name` values | `environment/production/permission_layer/sg.tf` |

**Finding:** `var.environment` is used by the RDS module and DB subnet group, but not consistently applied to VPC, subnet, EC2, and security-group resources. A repository-wide environment/component tagging standard remains a gap against the assignment criterion.

### 2.4 Manual Terraform execution

**Prerequisites:** Terraform `>= 1.13.0`, AWS credentials authorized for the target account, the existing S3 backend bucket `electro-terraform` in `us-east-1`, and the EC2 key pair configured in production variables. The backend bucket is not created by this Terraform configuration.

```bash
export AWS_PROFILE=your-aws-profile
read -r -p "RDS username: " TF_VAR_db_username
read -r -s -p "RDS password: " TF_VAR_db_password
printf '\n'
export TF_VAR_db_username TF_VAR_db_password

set -e
for layer in vpc_layer permission_layer ec2_layer rds_layer; do
  dir="environment/production/${layer}"
  terraform -chdir="$dir" init
  terraform -chdir="$dir" validate
  terraform -chdir="$dir" plan -out=tfplan
  terraform -chdir="$dir" apply tfplan
done

unset TF_VAR_db_username TF_VAR_db_password
```

**Operational caution:** Review each plan and AWS cost before applying. Database variables are marked sensitive, but credentials may still be represented in Terraform state; secure access to the remote state bucket.

---

## 3. Requirement B — Containerization Compliance

### 3.1 Multi-stage backend Dockerfile

The following excerpt is from `app/backend/Dockerfile`:

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-alpine
WORKDIR /app
USER node
COPY --chown=node:node --from=builder /app/node_modules ./node_modules
COPY --chown=node:node . .
EXPOSE 5000
CMD ["node", "server.js"]
```

| Criterion | Evidence / assessment |
| --- | --- |
| Multi-stage build | **Implemented:** `builder` stage installs production dependencies; runtime stage copies only application files and installed dependencies. |
| Non-root runtime | **Implemented:** runtime declares `USER node`; copies use `--chown=node:node`. |
| Image base | **Implemented:** both stages use `node:20-alpine`, a compact Alpine-based Node image. |
| Dependency installation | Dockerfile uses `npm ci --only=production`. **Build caveat:** `app/backend/` does not contain `package-lock.json`, which `npm ci` requires. |
| `.dockerignore` | **Not found:** no `.dockerignore` is present in `app/backend/` or repository root. Image build-context exclusions are not configured by a checked-in ignore file. |

**Why these choices:** Multi-stage builds avoid copying a separate build environment into runtime; Alpine limits the base image footprint; non-root execution reduces process privileges. Add a lockfile and a suitable `.dockerignore` to make the image build reproducible and reduce unnecessary build context.

### 3.2 Frontend image

`app/frontend/Dockerfile` uses `nginx:alpine`, replaces the default Nginx site configuration, copies `nginx.conf` and `index.html`, exposes port `80`, and starts Nginx in the foreground.

---

## 4. Requirement C — CI/CD Pipeline Compliance

### 4.1 Actual workflow coverage

The repository has separate backend, frontend, infrastructure-apply, and infrastructure-destroy workflows. It does not have `.github/workflows/deploy.yml`.

| Stage | Assignment criterion | Actual pipeline action and verification |
| --- | --- | --- |
| **1. Build** | Install backend dependencies with `npm ci`. | `.github/workflows/backend_pipe.yml` runs `npm install` in `app/backend`. It does not run `npm ci`. |
| **2. Test** | `npm test` runs `test.js`. | Workflow runs `node --check server.js` and `npm test --if-present`. `package.json` maps `npm test` to `node unit.js`; there is no `test.js`. `unit.js` contains basic runtime assertions and is not an API/database smoke test. |
| **3. Build & Push Image** | Tag with commit SHA and push to ECR. | Workflow logs into ECR using `aws-actions/amazon-ecr-login@v2`, then builds and pushes tag `v1.0.${{ github.run_number }}` to `electro_backend`. Frontend has a separate workflow pushing `electro_frontend`. Tags are run-number based, not commit-SHA based. |
| **4. Deploy** | `terraform apply` and `aws ecs update-service`. | **Not implemented in app workflows:** they locate an EC2 host tagged `Name=Test`, SSH as `ubuntu`, update a remote Compose image reference, then run `docker compose pull` and `docker compose up`. There is no `aws ecs update-service`. Terraform apply runs separately in manually dispatched `.github/workflows/infra.yml`, not as an application rolling deployment. |

The backend workflow's push trigger watches `app/backend/**` and `.github/workflows/backend.yml`, although the actual workflow filename is `backend_pipe.yml`. Both application workflows support manual dispatch. They use AWS region `us-east-1` and registry `557496517532.dkr.ecr.us-east-1.amazonaws.com`.

### 4.2 Implemented application pipeline commands

Backend checks in `.github/workflows/backend_pipe.yml`:

```bash
npm install
node --check server.js
npm test --if-present
```

Backend image publication:

```bash
docker build -t "$REGISTRY/$REPO:$IMAGE_TAG" .
docker push "$REGISTRY/$REPO:$IMAGE_TAG"
```

EC2 deployment commands executed remotely:

```bash
docker compose pull backend
docker compose up -d --no-deps --force-recreate backend
docker image prune -f
```

**Deployment mismatch:** Workflows search for an EC2 instance tagged `Name=Test`, while Terraform creates `Bastion_Host`, `Application_Tier`, and `Web_Tier`. They also expect `/home/ubuntu/docker-compose.yml` on the host; this repository's `app/docker_compose.yml` is empty.

### 4.3 Secrets management

The workflows reference GitHub Actions secrets rather than placing credential values directly in workflow YAML. The names and use actually present in the repository are:

| Secret | Purpose | Workflow usage |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | AWS API authentication. | Backend/frontend ECR and EC2 workflow steps; Terraform apply/destroy. |
| `AWS_SECRET_ACCESS_KEY` | AWS API authentication paired with the access key. | Backend/frontend ECR and EC2 workflow steps; Terraform apply/destroy. |
| `DB_PASSWORD` | RDS master password passed as `TF_VAR_db_password`. | Terraform apply and destroy RDS layer. |
| `DB_USERNAME` | RDS master username passed as `TF_VAR_db_username`. | Terraform apply and destroy RDS layer. |
| `EC2_SSH_KEY` | SSH private key for the remote EC2 deployment step. | Backend and frontend workflows. |

**Security qualification:** GitHub encrypted secrets avoid hardcoding values into source, but do not by themselves make Terraform state safe. Protect the S3 state bucket, restrict IAM access, and use narrowly scoped AWS credentials. `DB_USERNAME` and `EC2_SSH_KEY` are also required by the checked-in workflows even though they were not included in the example secret list.

---

## 5. Requirement D — Security and Monitoring Compliance

### 5.1 Logging and alerting

| Evaluation criterion | Requested implementation | Repository evidence / status |
| --- | --- | --- |
| CloudWatch logging | Log Group `/ecs/3tier-backend-api` with retention. | **Not implemented:** no CloudWatch log group, log stream, ECS logging configuration, or retention resource was found. |
| High-CPU alert | `aws_cloudwatch_metric_alarm.high_cpu_alarm`, threshold above 80%. | **Not implemented:** no CloudWatch metric alarm resource or CPU threshold configuration was found. |
| RDS monitoring | Database observability. | Performance Insights is enabled with 7-day retention. Enhanced Monitoring is disabled with `monitoring_interval = 0`. |
| Application logs | Logs from Express/API. | API uses `console.log` and `console.error`; no Terraform shipping configuration to CloudWatch is present. |

### 5.2 Security principles

| Principle | Assignment expectation | Actual configuration / assessment |
| --- | --- | --- |
| Least-privilege IAM | Dedicated `ecsTaskExecutionRole` with scoped permissions. | **Not implemented as specified:** there is no ECS task execution role. EC2 instance role attaches AWS managed `AmazonSSMManagedInstanceCore`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEC2ReadOnlyAccess`, and `AmazonRDSFullAccess` policies. Review and scope down permissions, especially RDS full access. |
| Port isolation | RDS TCP `5432` only from internal VPC range `10.0.0.0/16`. | **Not implemented:** RDS security group allows TCP `1433` from `0.0.0.0/0`; it is public-CIDR ingress and does not match PostgreSQL's default port. Private EC2 ingress also allows all protocols from `0.0.0.0/0`. |
| RDS network placement | Private subnets and no public DB exposure. | **Implemented:** RDS subnet group consumes private subnet IDs and `publicly_accessible = false`. |
| Encryption at rest | `storage_encrypted = true`. | **Not configured in code:** `storage_encrypted` is absent from `modules/rds/main.tf`. |
| Encryption in transit | Database connection over SSL. | **Partially implemented:** when `NODE_ENV=production`, `server.js` enables `pg` SSL with `rejectUnauthorized: false`. This enables TLS but disables server certificate verification; it is not full certificate-validated TLS. |

Relevant application TLS setting:

```javascript
ssl:
  process.env.NODE_ENV === "production"
    ? { rejectUnauthorized: false }
    : false,
```

**Why these controls matter:** Private placement reduces direct exposure, least-privilege rules limit lateral access, encryption protects data at rest and on the wire, and logs/alarms improve detection and response. The current code implements private RDS placement and conditional TLS, but the broad network rules, certificate-verification setting, absent storage encryption, and absent CloudWatch resources are material compliance gaps.

---

## 6. Overall Evaluation Summary

| Requirement area | Evidence-based result |
| --- | --- |
| Terraform modularity and VPC/RDS/EC2 provisioning | **Partially meets:** modular Terraform and VPC/RDS/EC2 are present; ECS Fargate and Terraform ECR provisioning are absent. |
| Containerization | **Partially meets:** multi-stage Alpine backend image and non-root runtime are present; lockfile and `.dockerignore` are absent. |
| CI/CD | **Partially meets:** GitHub Actions tests backend syntax/basic unit script and publishes ECR images; commit-SHA tags and ECS deployment are absent; deployment targets EC2. |
| Secrets | **Partially meets:** workflows reference GitHub encrypted secrets, including AWS and database credentials; state still requires protection. |
| Security and monitoring | **Partially meets / gaps:** RDS private placement and conditional DB TLS exist; least-privilege rules, explicit RDS encryption, CloudWatch log group, and high-CPU alarm are absent. |

**Conclusion:** The repository demonstrates a modular AWS Terraform foundation and an EC2-based container deployment path for a three-tier application. It does not currently demonstrate the assignment's ECS Fargate architecture or several named security/observability controls; those items should be implemented before claiming full compliance.

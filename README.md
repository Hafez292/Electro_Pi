# Electro Pi

![Node.js 20](https://img.shields.io/badge/Node.js-20-339933?logo=nodedotjs&logoColor=white)
![PostgreSQL 16](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)
![Terraform 1.13](https://img.shields.io/badge/Terraform-%3E%3D1.13-7B42BC?logo=terraform&logoColor=white)
![Docker](https://img.shields.io/badge/Containers-Docker-2496ED?logo=docker&logoColor=white)
![AWS](https://img.shields.io/badge/Cloud-AWS-232F3E?logo=amazonaws&logoColor=white)

Electro Pi is a three-tier web application assessment project. The frontend is a static page served by Nginx, the application tier is a Node.js/Express API, and the data tier is PostgreSQL. Terraform provisions AWS networking, EC2 instances, IAM/security-group resources, and an RDS database. GitHub Actions has separate workflows for application image deployment and infrastructure operations.

> **Deployment reality:** the runtime diagram below describes the application's intended request path. The checked-in AWS deployment provisions EC2 instances and the application workflows deploy to EC2 over SSH; there is no ECS service or task definition in this repository. Some requested local/production capabilities are not yet configured; see the notes in the relevant sections.

## Architecture overview

```text
                         Presentation tier
  Browser ──HTTP :80──> Nginx frontend (static HTML)
                              │
                              │ /api/* reverse proxy
                              ▼
                         Application tier
                Node.js / Express API :5000 <── GET /health
                              │
                              │ SQL: SELECT NOW()
                              ▼
                       Data tier
                  AWS RDS PostgreSQL :5432
```

The frontend calls `/api/data` using a relative URL. Nginx serves the static page and proxies `/api/` requests to the upstream named `backend-api` on port `5000`. The API uses the `pg` connection pool and environment variables to connect to PostgreSQL. In the Terraform environment, EC2 instances are created for the web tier, application tier, and a bastion host, while RDS is configured as a private PostgreSQL instance.

## Repository structure

```text
.
├── app/
│   ├── backend/
│   │   ├── Dockerfile             # Node 20 Alpine multi-stage API image
│   │   ├── package.json           # Express, CORS, PostgreSQL client and npm scripts
│   │   ├── server.js              # Express routes and PostgreSQL pool
│   │   └── unit.js                # Minimal Node test script
│   ├── frontend/
│   │   ├── Dockerfile             # Nginx Alpine static-site image
│   │   ├── index.html             # Demo UI; calls /api/data
│   │   └── nginx.conf             # Static hosting and /api/ proxy
│   └── docker_compose.yml         # Currently empty; no Compose services are defined
├── environment/
│   └── production/
│       ├── vpc_layer/             # VPC, subnets, routes; remote state in S3
│       ├── permission_layer/      # Security groups and EC2 IAM role/profile
│       ├── ec2_layer/             # Bastion, application-tier, and web-tier EC2 instances
│       └── rds_layer/             # Private RDS PostgreSQL instance
├── modules/
│   ├── ec2/                       # Reusable Ubuntu EC2 instance
│   ├── rds/                       # Reusable RDS PostgreSQL instance and subnet group
│   └── vpc/                       # VPC, public/private subnets, gateways, and route tables
├── .github/
│   └── workflows/
│       ├── backend_pipe.yml       # Backend test, ECR push, and EC2 deployment
│       ├── frontend_pipeline.yml  # Frontend ECR push and EC2 deployment
│       ├── infra.yml              # Manually dispatched Terraform apply
│       └── destroy_ifra_prod.yml  # Manually dispatched Terraform destroy
└── README.md
```

Terraform modules are in the repository-root `modules/` directory, not `terraform/modules/`. The layer configurations are under `environment/production/`. The Compose file is named `app/docker_compose.yml` (underscore), not a root-level `docker-compose.yml`.

## Infrastructure as Code (Terraform)

Terraform is split into four production layers. Each layer has its own Terraform configuration and S3 state key in the `electro-terraform` bucket in `us-east-1`. The configurations require Terraform `>= 1.13.0` and AWS provider `6.28.0`.

| Layer/module | Resources and purpose |
| --- | --- |
| `modules/vpc` | VPC, public/private subnets, Internet Gateway, NAT Gateway, Elastic IP, route tables, and subnet associations. |
| `modules/ec2` | Ubuntu 24.04 EC2 instance using the requested instance type, subnet, security group, key pair, optional IAM profile, and a `gp3` root volume. |
| `modules/rds` | PostgreSQL 16.3 RDS instance and DB subnet group, using `gp3` storage with 20 GB allocated and a 100 GB autoscaling maximum. It is configured as non-public and single-AZ. |
| `environment/production/permission_layer` | Security groups plus an EC2 instance role/profile. The role has SSM, ECR read-only, EC2 read-only, and RDS full-access managed policies attached. |

The production EC2 layer instantiates the EC2 module three times: `Bastion_Host`, `Application_Tier`, and `Web_Tier`. VPC, permission, EC2, and RDS state are read separately through Terraform's S3 remote-state data sources. There are no Terraform ECS or ECR modules in this checkout; the application workflows assume the ECR repositories already exist.

### Security and monitoring configuration

- RDS is placed in private subnets and has `publicly_accessible = false`.
- RDS Performance Insights is enabled with a 7-day retention period. RDS Enhanced Monitoring is disabled (`monitoring_interval = 0`).
- The Terraform does **not** define CloudWatch alarms or explicitly enable RDS storage encryption (`storage_encrypted` is not set).
- The configured security groups are **not least-privilege**: the private EC2 group allows all inbound traffic from `0.0.0.0/0`; the public group includes all-protocol ingress from `0.0.0.0/0` and SSH from anywhere; and the RDS group opens TCP `1433` to `0.0.0.0/0`. PostgreSQL normally listens on `5432`, so the RDS rule also does not match the application's default DB port. Review and restrict these rules before using this configuration in a production environment.
- Terraform marks database credentials as sensitive inputs, but credentials can still be stored in Terraform state. Protect the S3 state bucket and its access; do not commit credentials or state files.

### Run Terraform locally

Prerequisites: Terraform `1.13` or later, AWS CLI credentials authorized for the target account, an existing accessible S3 bucket named `electro-terraform` in `us-east-1`, and the EC2 key pair referenced by `environment/production/ec2_layer/terraform.tfvars`. The S3 backend bucket is not created by these configurations.

Set AWS credentials through your normal AWS profile/environment, then provide the RDS credentials without committing them. For example, the following prompts avoid echoing the password:

```bash
export AWS_PROFILE=your-aws-profile
read -r -p "RDS username: " TF_VAR_db_username
read -r -s -p "RDS password: " TF_VAR_db_password
printf '\n'
export TF_VAR_db_username TF_VAR_db_password
```

Initialize, validate, plan, and apply each layer in dependency order. Review each plan before approving the apply:

```bash
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

Each layer uses remote state, so run them in order and ensure the prerequisite state has been applied. `terraform apply` provisions billable AWS resources. The repository also contains a manually dispatched workflow at `.github/workflows/destroy_ifra_prod.yml` that runs `terraform destroy`; use it only when intentional teardown is required.

## Containerization and local execution

### Backend image

`app/backend/Dockerfile` uses `node:20-alpine` in a two-stage build. It installs production dependencies in the builder stage and copies the resulting `node_modules` and app into the runtime stage. The runtime switches to the non-root `node` user and exposes port `5000`.

There is currently no `package-lock.json` in `app/backend/`, but the Dockerfile runs `npm ci`. `npm ci` requires a lockfile, so generate and commit a lockfile before expecting the backend image build to succeed.

### Frontend image

`app/frontend/Dockerfile` uses `nginx:alpine`, copies the static HTML and custom Nginx configuration, and serves on port `80`. Nginx forwards `/api/` to `http://backend-api:5000/api/`; therefore the backend container/service must be addressable as `backend-api` on a shared container network.

### Docker Compose status and commands

`app/docker_compose.yml` is currently a zero-byte file. It defines no frontend, API, or database services, so there is not yet a runnable Compose stack in this repository. The correct Compose CLI syntax for this non-default file is:

```bash
# These commands are ready to use once app/docker_compose.yml defines the services.
docker compose -f app/docker_compose.yml build
docker compose -f app/docker_compose.yml up --detach
docker compose -f app/docker_compose.yml logs --follow
docker compose -f app/docker_compose.yml down
```

At present, Compose cannot build or start the three-tier application from that file. A working local stack needs service definitions for the frontend, the API (with `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, and `DB_PORT` configured), and PostgreSQL, plus port mappings and service networking. No local database service or Compose health/dependency checks are currently configured.

The API's database defaults are `DB_NAME=appdnb` and `DB_PORT=5432`; `DB_HOST`, `DB_USER`, and `DB_PASSWORD` must be supplied. In production (`NODE_ENV=production`) the `pg` client enables TLS with certificate verification disabled. Set the database name to one that actually exists on the target RDS instance.

## CI/CD (GitHub Actions)

The repository uses separate workflows rather than one four-stage ECS pipeline:

| Workflow | Trigger and behavior |
| --- | --- |
| `backend_pipe.yml` | Push to `main` affecting `app/backend/**`, or manual dispatch. Installs dependencies, checks JavaScript syntax, runs `npm test`, builds and pushes an image tagged `v1.0.<run number>` to ECR, then connects over SSH and recreates the backend container on an EC2 host. |
| `frontend_pipeline.yml` | Push to `main` affecting `app/frontend/**`, or manual dispatch. Builds and pushes a versioned image to ECR, then connects over SSH and recreates the frontend container on EC2. It does not define a separate frontend test step. |
| `infra.yml` | Manual dispatch only. Initializes, validates, plans, and applies the VPC, permissions, EC2, and RDS Terraform layers in that order. |
| `destroy_ifra_prod.yml` | Manual dispatch only. Destroys the RDS, EC2, permissions, and VPC layers in reverse dependency order. |

The backend workflow's stages are approximately **Install/check/test → Build and push to ECR → Deploy to EC2**. Frontend deployment has **Build and push → Deploy to EC2**. Neither app workflow deploys to ECS. Both workflows use AWS region `us-east-1`, ECR registry `557496517532.dkr.ecr.us-east-1.amazonaws.com`, and repositories `electro_backend` / `electro_frontend`. The registry and repository names are configured in workflow files, not provisioned by Terraform here.

The backend push trigger also lists `.github/workflows/backend.yml` as a watched path, but the workflow file in this repository is `backend_pipe.yml`; changing only the workflow file therefore does not match that path filter. The backend app path and manual-dispatch triggers are present.

### GitHub Actions secrets

Add these secrets under the repository's **Settings → Secrets and variables → Actions**:

| Secret | Used for |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | AWS credentials for image publishing and Terraform workflows. |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for image publishing and Terraform workflows. |
| `DB_USERNAME` | Passed as `TF_VAR_db_username` to the Terraform apply/destroy RDS layer. |
| `DB_PASSWORD` | Passed as `TF_VAR_db_password` to the Terraform apply/destroy RDS layer. |
| `EC2_SSH_KEY` | SSH private key used by the backend and frontend deployment workflows. |

GitHub secrets are referenced through the Actions secrets context rather than embedded as credential literals in the workflow. Terraform database variables are marked sensitive and passed via environment variables; they may nevertheless be present in Terraform state. Use narrowly scoped AWS credentials and protect both the repository secrets and remote state.

> **Deployment prerequisites to verify:** the application workflows discover an instance tagged `Name=Test`, while the Terraform EC2 module creates instances named `Bastion_Host`, `Application_Tier`, and `Web_Tier`. They also SSH to `/home/ubuntu` and update a remote `docker-compose.yml`; that host-side Compose file is not present in this repository. Ensure the target host, ECR repositories, image deployment configuration, and required database environment are provisioned consistently before dispatching these workflows.

## API and health checks

| Method | Path | Behavior |
| --- | --- | --- |
| `GET` | `/health` | Returns HTTP 200 with `{ "status": "healthy", "timestamp": ... }`. This is a process-level check and does not query the database. |
| `GET` | `/api/data` | Runs `SELECT NOW()` and returns a greeting plus the database time. On query failure, returns HTTP 500. |

Examples when the API is reachable on local port `5000`:

```bash
curl http://localhost:5000/health
curl http://localhost:5000/api/data
```

Through the Nginx frontend, `/api/data` is proxied to the API:

```bash
curl http://localhost/api/data
```

Nginx only proxies `/api/`; `/health` is served by Express on the API listener and is not routed by the checked-in Nginx configuration.

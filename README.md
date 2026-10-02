# ⚡ Electro Pi

![Node.js 20](https://img.shields.io/badge/Node.js-20-339933?logo=nodedotjs&logoColor=white)
![PostgreSQL 16](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)
![Terraform 1.13](https://img.shields.io/badge/Terraform-%3E%3D1.13-7B42BC?logo=terraform&logoColor=white)
![Docker](https://img.shields.io/badge/Containers-Docker-2496ED?logo=docker&logoColor=white)
![AWS](https://img.shields.io/badge/Cloud-AWS-232F3E?logo=amazonaws&logoColor=white)

## 🗂️ Repository hierarchy

```text
Electro Pi/
├── .github/
│   └── workflows/
├── app/
│   ├── backend/
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   ├── server.js
│   │   └── unit.js
│   ├── frontend/
│   │   ├── Dockerfile
│   │   ├── index.html
│   │   └── nginx.conf
│   └── docker_compose.yml
├── environment/
│   └── production/
│       ├── ec2_layer/
│       ├── permission_layer/
│       ├── rds_layer/
│       └── vpc_layer/
├── modules/
│   ├── ec2/
│   ├── rds/
│   └── vpc/
├── README.md
└── .git/
```

## ⚙️ Running the project

### Local development

The repository is designed around a simple three-tier flow: a static frontend, a Node.js API, and a PostgreSQL database.

1. Start the backend service:

   ```bash
   cd app/backend
   npm install
   export DB_HOST=localhost
   export DB_USER=postgres
   export DB_PASSWORD=yourpassword
   export DB_NAME=appdnb
   export DB_PORT=5432
   npm start
   ```

   Once running, verify the health check and data endpoint:

   ```bash
   curl http://localhost:5000/health
   curl http://localhost:5000/api/data
   ```

2. Serve the frontend:

   - The static page is served by the browser directly from `app/frontend/index.html`, or
   - build and run the container image:

   ```bash
   docker build -t electro-frontend ./app/frontend
   docker run --rm -p 80:80 electro-frontend
   ```

3. Use Docker Compose once the file is populated with services:

   ```bash
   docker compose -f app/docker_compose.yml up --build
   ```

   The current `app/docker_compose.yml` is intentionally empty, so a full local stack is not runnable until services, networking, and environment variables are added.

### Cloud deployment

The production cloud design is provisioned with Terraform under `environment/production/` and deployed with GitHub Actions.

1. Prepare the required AWS prerequisites:
   - an existing S3 remote-state bucket named `electro-terraform` in `us-east-1`
   - a valid EC2 key pair configured in `environment/production/ec2_layer/terraform.tfvars`
   - AWS credentials available to Terraform and the GitHub Action runners

2. Apply the infrastructure layers in order:

   ```bash
   terraform -chdir=environment/production/vpc_layer init
   terraform -chdir=environment/production/vpc_layer apply

   terraform -chdir=environment/production/permission_layer init
   terraform -chdir=environment/production/permission_layer apply

   terraform -chdir=environment/production/rds_layer init
   terraform -chdir=environment/production/rds_layer apply

   terraform -chdir=environment/production/ec2_layer init
   terraform -chdir=environment/production/ec2_layer apply
   ```

3. Deploy application images through the workflow files in `.github/workflows/`:
   - `backend_pipe.yml` builds and pushes the backend image to Amazon ECR and deploys it to the EC2 host over SSH.
   - `frontend_pipeline.yml` does the same for the statically served frontend.

## 🧭 Architectural decisions and rationale

- Simple three-tier separation: presentation, application, and data are kept independent so the frontend, API, and database can evolve without coupling each layer to the others.
- Nginx as the public entry point: it serves the static UI and forwards `/api/*` requests to the backend, which is a clean and low-cost pattern for a demo workload.
- Express + PostgreSQL integration: the backend keeps the database access logic centralized in one service, using a connection pool and a small `/api/data` query that demonstrates the end-to-end path.
- Terraform layered by concern: networking, permissions, RDS, and EC2 are split into separate directories to align with infrastructure responsibilities and make the deployment easier to reason about.
- CI/CD through GitHub Actions to EC2: the repository targets EC2-based deployment rather than ECS/Kubernetes to match the checked-in infrastructure and keep the workload straightforward for an assessment.

## ⚠️ Trade-offs and time-limit constraints

- The local Compose stack is intentionally not ready: `app/docker_compose.yml` is empty, so there is no complete local multi-container stack yet.
- The architecture chooses a minimal API surface instead of a richer service layer; this keeps setup lightweight and avoids unnecessary abstraction for a small assessment project.
- Cloud deployment is simplified to EC2 and RDS rather than a fully managed container orchestration service, which reduces operational complexity for the current scope but gives up some resilience and autoscaling features.
- Observability, security hardening, and production reliability patterns are intentionally limited: there is no full monitoring stack, no advanced auth model, and no full database migration workflow in the checked-in code.

Electro Pi is a three-tier web application assessment project with a static Nginx frontend, a Node.js/Express API, and PostgreSQL. Terraform provisions AWS networking, EC2, IAM/security-group resources, and a private RDS database, while GitHub Actions provides application-image deployment and infrastructure workflows.

> **Deployment note:** the intended application flow is Nginx → Express API → PostgreSQL. The checked-in AWS deployment provisions EC2 and deploys to EC2 over SSH; there is no ECS service or task definition in this repository. The Compose file is empty, and some local/production capabilities are not yet configured; those limitations are called out below.

---

## 🏗️ Architecture at a glance

```text
                         PRESENTATION TIER
  Browser ── HTTP :80 ──> Nginx frontend (static HTML)
                                 │
                                 │ /api/* reverse proxy
                                 ▼
                         APPLICATION TIER
                 Node.js / Express API :5000 <── GET /health
                                 │
                                 │ SQL: SELECT NOW()
                                 ▼
                            DATA TIER
                    AWS RDS PostgreSQL :5432
```

| Tier | Component | Responsibility | Configuration |
| --- | --- | --- | --- |
| **Presentation** | Nginx frontend | Serves the static page and proxies `/api/` to the backend. | `app/frontend/index.html`, `app/frontend/nginx.conf`; listens on port `80`, upstream `backend-api:5000`. |
| **Application** | Node.js / Express | Exposes health and data endpoints; uses the `pg` pool to access PostgreSQL. | `app/backend/server.js`; default port `5000`; environment-configured DB connection. |
| **Data** | AWS RDS PostgreSQL | Stores application data; the current example query returns the database server time. | Terraform module configures PostgreSQL `16.3`, private subnets, and port `5432` as the application default. |

The frontend calls `/api/data` with a relative URL. Nginx proxies `/api/` requests to `http://backend-api:5000/api/`. The API's `/health` route checks that the process responds, while `/api/data` executes `SELECT NOW()`. The production Terraform EC2 layer creates instances named `Bastion_Host`, `Application_Tier`, and `Web_Tier`, alongside the private RDS instance.

---

## 🗺️ Repository map

<details>
<summary>Expand the annotated repository tree</summary>

```text
.
├── app/
│   ├── backend/
│   │   ├── Dockerfile             # Node 20 Alpine multi-stage API image
│   │   ├── package.json           # Express, CORS, pg, start/test scripts
│   │   ├── server.js              # Express routes and PostgreSQL pool
│   │   └── unit.js                # Minimal Node test script
│   ├── frontend/
│   │   ├── Dockerfile             # Nginx Alpine static-site image
│   │   ├── index.html             # Demo UI; calls /api/data
│   │   └── nginx.conf             # Static hosting and /api/ reverse proxy
│   └── docker_compose.yml         # Zero-byte file; no services are defined
├── environment/
│   └── production/
│       ├── vpc_layer/             # VPC, subnets, routes; S3 remote state
│       ├── permission_layer/      # Security groups and EC2 IAM role/profile
│       ├── ec2_layer/             # Bastion, app-tier, and web-tier EC2 instances
│       └── rds_layer/             # Private RDS PostgreSQL instance
├── modules/
│   ├── ec2/                       # Reusable Ubuntu EC2 instance
│   ├── rds/                       # RDS PostgreSQL instance and subnet group
│   └── vpc/                       # VPC, subnets, gateways, and route tables
├── .github/
│   └── workflows/
│       ├── backend_pipe.yml       # Backend test, ECR push, EC2 deployment
│       ├── frontend_pipeline.yml  # Frontend ECR push and EC2 deployment
│       ├── infra.yml              # Manual Terraform apply workflow
│       └── destroy_ifra_prod.yml  # Manual Terraform destroy workflow
└── README.md
```

</details>

Terraform modules are in the repository-root **`modules/`** folder, not `terraform/modules/`. Layer configurations are under **`environment/production/`**. The Compose file is **`app/docker_compose.yml`** (underscore), not a root-level `docker-compose.yml`.

---

## 🚀 Prerequisites & quickstart

### Prerequisites

| Tool / dependency | Purpose |
| --- | --- |
| Docker Engine and Docker Compose plugin | Build and run the container stack once Compose services are defined. |
| Node.js 20 and npm | Run backend checks and tests locally. |
| Terraform `>= 1.13.0` and AWS CLI credentials | Optional: provision the production AWS environment. |
| AWS S3 bucket `electro-terraform` in `us-east-1` | Existing remote-state backend; Terraform does not create this bucket. |
| EC2 key pair configured in `environment/production/ec2_layer/terraform.tfvars` | Required by the production EC2 layer. |

### Local development

1. **Inspect the Compose configuration.** `app/docker_compose.yml` is currently zero bytes. It defines no frontend, API, or database services, so the full Compose stack cannot currently be built or started.
2. **Run the available backend checks** from the backend directory:

   ```bash
   cd app/backend
   npm install
   node --check server.js
   npm test --if-present
   ```

   The API requires a reachable PostgreSQL database and `DB_HOST`, `DB_USER`, and `DB_PASSWORD` at runtime. The values of `DB_NAME` and `DB_PORT` default to `appdnb` and `5432`.
3. **Use the Compose commands below when the file contains service definitions.** A runnable local stack needs frontend, API, and PostgreSQL services, port mappings, shared networking, and the backend database variables.

<details>
<summary>Docker Compose commands (after defining services)</summary>

```bash
docker compose -f app/docker_compose.yml build
docker compose -f app/docker_compose.yml up --detach
docker compose -f app/docker_compose.yml logs --follow
docker compose -f app/docker_compose.yml down
```

</details>

### Container configuration

| Image | Implemented practices and behavior |
| --- | --- |
| Backend — `app/backend/Dockerfile` | Two-stage build using `node:20-alpine`; installs production dependencies in the builder stage; copies app and `node_modules` to the runtime stage; runs as non-root `USER node`; exposes port `5000`. |
| Frontend — `app/frontend/Dockerfile` | Uses `nginx:alpine`; removes the default site/config, copies the custom Nginx config and HTML, exposes port `80`, and runs Nginx in the foreground. |

> **Backend image build caveat:** the Dockerfile uses `npm ci`, which requires a lockfile. There is no `package-lock.json` in `app/backend/` at present; generate and commit one before relying on the image build.

### Backend environment variables

| Variable | Required? | Default / use |
| --- | --- | --- |
| `PORT` | No | API listen port; defaults to `5000`. |
| `DB_HOST` | Yes | PostgreSQL hostname or RDS endpoint. |
| `DB_USER` | Yes | PostgreSQL username. |
| `DB_PASSWORD` | Yes | PostgreSQL password. |
| `DB_NAME` | No | Database name; defaults to `appdnb`. Set to an existing database on the target RDS instance. |
| `DB_PORT` | No | PostgreSQL port; defaults to `5432`. |
| `NODE_ENV` | No | When set to `production`, `pg` TLS is enabled with `rejectUnauthorized: false`. |

No local database service or Compose health/dependency checks are currently configured.

---

## ☁️ Infrastructure & security (Terraform)

Terraform is organized into four production layers. The layer configurations require Terraform **`>= 1.13.0`** and AWS provider **`6.28.0`**, use region **`us-east-1`**, and store state in the S3 bucket **`electro-terraform`**. The `modules/` folder contains the reusable resource modules; each environment layer composes those modules and reads dependencies through remote state.

### Modules and layers

| Module / layer | Provisions | Notable configuration |
| --- | --- | --- |
| `modules/vpc` | VPC, public/private subnets, Internet Gateway, NAT Gateway, Elastic IP, route tables, and subnet associations. | Production VPC CIDR `10.0.0.0/16`; public subnets `10.0.1.0/24`, `10.0.2.0/24`; private subnets `10.0.3.0/24`, `10.0.4.0/24`; AZ list `us-east-1a`, `us-east-1d`, `us-east-1c`; DNS hostnames enabled. |
| `modules/ec2` | Ubuntu 24.04 EC2 instance with a selected subnet, security group, key pair, optional IAM instance profile, and root volume. | Production layer creates `Bastion_Host`, `Application_Tier`, and `Web_Tier`; production tfvars set `t3.micro`, key pair `7ader`, 20 GB `gp3` root volume, and production tags. Module defaults include `t2.micro` and an 8 GB `gp3` volume. |
| `modules/rds` | RDS instance and DB subnet group. | PostgreSQL `16.3`, `db.t3.medium`, 20 GB `gp3` storage with max autoscaling allocation 100 GB, private (`publicly_accessible = false`), single-AZ. |
| `environment/production/permission_layer` | Security groups, EC2 IAM role, and instance profile. | The role attaches `AmazonSSMManagedInstanceCore`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEC2ReadOnlyAccess`, and `AmazonRDSFullAccess`. |
| `environment/production/{vpc,permission,ec2,rds}_layer` | Environment-specific composition, provider/backend config, variables, and outputs for the respective layer. | S3 state keys: `vpc/terraform.tfstate`, `permission/terraform.tfstate`, `ec2/terraform.tfstate`, `rds/terraform.tfstate`. |

There are no Terraform **ECS** or **ECR** modules in this checkout. The application workflows expect ECR repositories to already exist.

### Security and monitoring

> **Production review required:** the checked-in network rules are not least-privilege. Restrict the exposed ingress before deploying this configuration in a production environment.

| Control | Current configuration |
| --- | --- |
| RDS network placement | RDS uses private subnets and `publicly_accessible = false`. |
| Security groups | Private EC2 ingress allows all protocols from `0.0.0.0/0`; the public group allows all-protocol ingress and SSH (`22`) from `0.0.0.0/0` (as well as HTTP `80` and HTTPS `443`); the RDS group allows TCP `1433` from `0.0.0.0/0`. PostgreSQL normally listens on `5432`, so the RDS ingress rule does not match the application's default DB port. |
| Database monitoring | Performance Insights enabled with 7-day retention. Enhanced Monitoring disabled (`monitoring_interval = 0`). |
| CloudWatch alarms | No CloudWatch alarms are defined in the Terraform configuration. |
| Encryption at rest | The RDS module does not explicitly set `storage_encrypted`; encryption at rest is not configured in code. |
| Credentials and state | DB variables are marked `sensitive` and passed via environment variables in Actions, but credentials may still be present in Terraform state. Protect the remote S3 bucket and its access; do not commit credentials or state files. |

### Terraform local workflow

Use an AWS profile or environment credentials authorized for the target account. The S3 backend bucket must already exist, and the EC2 key pair referenced in the production variables must be available. The following commands prompt for the DB credentials without echoing the password:

<details>
<summary>Expand local Terraform init, validate, plan, and apply commands</summary>

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

</details>

Apply layers in dependency order and review each plan before approving its apply. Each layer consumes outputs from previously applied remote state. `terraform apply` creates billable AWS resources. The manually dispatched **`.github/workflows/destroy_ifra_prod.yml`** workflow runs Terraform destroy in reverse dependency order; use it only for intentional teardown.

---

## 🔄 CI/CD pipeline workflow

There is no single four-stage ECS pipeline. Application workflows are separate and target EC2. The stage table below maps the requested **Build → Test → Package → Deploy** structure to what is actually present:

| Stage | Backend workflow — `backend_pipe.yml` | Frontend workflow — `frontend_pipeline.yml` |
| --- | --- | --- |
| **Build / setup** | Checks out the repository and sets up Node.js `20`. | Checks out the repository. |
| **Test** | Runs `npm install`, `node --check server.js`, and `npm test --if-present` in `app/backend`. | No separate frontend test step is configured. |
| **Package** | Builds a Docker image and pushes tag `v1.0.<run number>` to ECR repository `electro_backend`. | Builds a Docker image and pushes tag `v1.0.<run number>` to ECR repository `electro_frontend`. |
| **Deploy** | Looks up a running EC2 instance tagged `Name=Test`, SSHes as `ubuntu`, logs in to ECR, updates the backend image reference in `/home/ubuntu/docker-compose.yml`, then pulls/recreates the backend container and prunes unused images. | Looks up a running EC2 instance tagged `Name=Test`, SSHes as `ubuntu`, logs in to ECR, updates the frontend image reference in `/home/ubuntu/docker-compose.yml`, then pulls/recreates the frontend container and prunes unused images. |

Both image workflows use AWS region **`us-east-1`** and registry **`557496517532.dkr.ecr.us-east-1.amazonaws.com`**. ECR repositories are configured in the workflows, not provisioned by Terraform. The backend workflow triggers on pushes to `main` affecting `app/backend/**` or manual dispatch; its watched workflow path is `.github/workflows/backend.yml`, while the actual file is `backend_pipe.yml`. The frontend workflow triggers on pushes to `main` affecting `app/frontend/**` or manual dispatch.

<details>
<summary>Detailed application workflow steps and deployment commands</summary>

**Backend (`backend_pipe.yml`):**

1. Runs on `ubuntu-latest`, checks out the repository, and sets up Node.js `20`.
2. In `app/backend/`, runs `npm install`, `node --check server.js`, and `npm test --if-present`.
3. Configures AWS credentials, logs into ECR with `aws-actions/amazon-ecr-login@v2`, then builds and pushes:

   ```bash
   docker build -t "$REGISTRY/$REPO:$IMAGE_TAG" .
   docker push "$REGISTRY/$REPO:$IMAGE_TAG"
   ```

4. Uses `aws ec2 describe-instances` with `Name=tag:Name,Values=Test` and `Name=instance-state-name,Values=running` to locate a public IP; the job fails if none is found.
5. Uses `appleboy/ssh-action@v1.0.3` to connect as `ubuntu` with `EC2_SSH_KEY`, authenticate Docker to ECR, update the image tag in `/home/ubuntu/docker-compose.yml`, and redeploy:

   ```bash
   docker compose pull backend
   docker compose up -d --no-deps --force-recreate backend
   docker image prune -f
   docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
   ```

**Frontend (`frontend_pipeline.yml`):**

1. Runs on `ubuntu-latest` and checks out the repository. No Node setup or test step is configured.
2. Configures AWS credentials, logs into ECR, and builds/pushes the frontend image using `REPO=electro_frontend` and the same `v1.0.<run number>` tag scheme.
3. Performs the same `Name=Test` running-instance/public-IP lookup and uses `appleboy/ssh-action@v1.0.3` with `EC2_SSH_KEY`.
4. Updates the `electro_frontend` image tag in the remote Compose file, then runs `docker compose pull frontend`, `docker compose up -d --no-deps --force-recreate frontend`, `docker image prune -f`, and the same `docker ps` status listing.

</details>

The infrastructure workflow **`infra.yml`** is manually dispatched. It sets up Terraform `1.13`, then initializes, validates, plans, and applies the VPC, permissions, EC2, and RDS layers in order. The manually dispatched **`destroy_ifra_prod.yml`** workflow destroys RDS, EC2, permissions, then VPC. Both infrastructure workflows configure AWS credentials for `us-east-1`; they pass DB credentials as Terraform environment variables for the RDS layer.

> **Deployment prerequisites to verify:** app workflows search for an instance tagged `Name=Test`, but Terraform names instances `Bastion_Host`, `Application_Tier`, and `Web_Tier`. The workflows also expect a host-side `/home/ubuntu/docker-compose.yml`, which is not the repository's empty `app/docker_compose.yml`. Confirm the target host, ECR repositories, Compose deployment file, and backend DB environment before dispatching either workflow.

### 🔐 Secrets management

Add the required secrets under **Repository Settings → Secrets and variables → Actions**. GitHub Actions references them through the secrets context rather than hardcoding credential values in the workflow files.

| Secret | Purpose | Required by |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | AWS access key used by workflows to authenticate. | Backend image publish/deploy, frontend image publish/deploy, Terraform apply/destroy. |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key used with the access key. | Backend image publish/deploy, frontend image publish/deploy, Terraform apply/destroy. |
| `DB_USERNAME` | Passed as `TF_VAR_db_username` to the Terraform RDS layer. | Infrastructure apply and destroy workflows. |
| `DB_PASSWORD` | Passed as `TF_VAR_db_password` to the Terraform RDS layer. | Infrastructure apply and destroy workflows. |
| `EC2_SSH_KEY` | SSH private key for remote container deployment. | Backend and frontend image workflows. |

Use narrowly scoped AWS credentials. Terraform's sensitive variables do not prevent values from being stored in state, so secure the S3 backend and restrict access to it.

---

## 📡 API reference

| Method | Endpoint | Behavior | Sample response |
| --- | --- | --- | --- |
| `GET` | `/health` | Process-level check; returns HTTP `200` and does not query PostgreSQL. | `{"status":"healthy","timestamp":"<current timestamp>"}` |
| `GET` | `/api/data` | Executes `SELECT NOW()` and returns a greeting with the database time. Returns HTTP `500` if the DB query fails. | `{"message":"Hello from the Backend API!","db_time":"<database timestamp>"}` |

Run the API on port `5000` and query it directly:

```bash
curl http://localhost:5000/health
curl http://localhost:5000/api/data
```

When Nginx is available on port `80`, the API route can also be requested through the frontend:

```bash
curl http://localhost/api/data
```

Nginx proxies `/api/` only. `/health` is served by Express on the API listener and is not routed through the checked-in Nginx configuration.

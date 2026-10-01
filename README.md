# 3-Tier Application Infrastructure & Deployment Guide

**Project:** Electro Pi
**Guide purpose:** Explain the application, AWS infrastructure, deployment workflows, and operational checks represented by this repository.

Electro Pi demonstrates a three-tier web application: a static Nginx presentation tier, a Node.js/Express application tier, and a PostgreSQL data tier. The guiding principles are separation of responsibilities, containerized application components, reusable Terraform modules, and automated image delivery; this guide also identifies where the current checkout does not yet implement the intended production controls or orchestration.

> **Repository accuracy note:** Terraform provisions VPC, EC2, IAM/security-group resources, and private RDS PostgreSQL. It does **not** provision ECS, ECR, CloudWatch alarms, or encryption-at-rest settings. The application workflows deploy to EC2 over SSH, not ECS. `app/docker_compose.yml` is empty, so the full stack is not currently runnable with Compose. Security-group rules are broad rather than least-privilege.

---

## Step 1 — Application Architecture & Containerization Setup

### 1.1 Request flow

```text
┌──────────────────────┐       HTTP :80        ┌────────────────────────┐
│ Browser / user       │ ─────────────────────>│ Presentation           │
└──────────────────────┘                       │ Nginx static frontend  │
                                               └───────────┬────────────┘
                                                           │ /api/*
                                                           ▼
                                               ┌────────────────────────┐
                                               │ Application            │
                                               │ Node.js / Express :5000│
                                               └───────────┬────────────┘
                                                           │ SQL
                                                           │ SELECT NOW()
                                                           ▼
                                               ┌────────────────────────┐
                                               │ Data                   │
                                               │ AWS RDS PostgreSQL     │
                                               │ :5432                  │
                                               └────────────────────────┘
```

| Tier | Implementation | Request responsibility |
| --- | --- | --- |
| **Presentation** | `app/frontend/index.html`, `app/frontend/Dockerfile`, `app/frontend/nginx.conf` | Nginx serves the single-page demo and proxies `/api/` to `backend-api:5000`. |
| **Application** | `app/backend/server.js`, `app/backend/Dockerfile` | Express serves `/health` and `/api/data`, using `pg` to query PostgreSQL. |
| **Data** | `modules/rds/` and `environment/production/rds_layer/` | RDS PostgreSQL `16.3`; private subnets; Terraform sets `publicly_accessible = false`. |

**Why this was done:** Keeping presentation, request handling, and persistence in separate tiers provides clear ownership boundaries and lets the UI call the API without exposing database access to browsers. The current frontend uses a relative API path, so the browser calls the same Nginx origin and Nginx performs the upstream routing.

### 1.2 Frontend — Nginx

The following is from `app/frontend/nginx.conf`:

```nginx
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://backend-api:5000/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

The frontend image is built from `nginx:alpine`, copies this configuration and `index.html`, and exposes port `80`. The upstream name `backend-api` must resolve on the container network in any Compose or runtime configuration.

**Why this was done:** Nginx serves static content efficiently and provides a same-origin reverse proxy for `/api/`. It reduces browser-side routing complexity; it does not route `/health` in the current configuration.

### 1.3 Backend — Node.js / Express

The database pool and routes below are excerpted from `app/backend/server.js`:

```javascript
const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || "appdnb",
  port: process.env.DB_PORT || 5432,
  ssl:
    process.env.NODE_ENV === "production"
      ? { rejectUnauthorized: false }
      : false,
});

app.get("/health", (req, res) => {
  res.status(200).json({ status: "healthy", timestamp: new Date() });
});

app.get("/api/data", async (req, res) => {
  try {
    const result = await pool.query("SELECT NOW()");
    res.json({
      message: "Hello from the Backend API!",
      db_time: result.rows[0].now,
    });
  } catch (err) {
    console.error("Database query error:", err.message);
    res.status(500).json({
      error: "Database connection failed",
      details: err.message,
    });
  }
});
```

| Environment variable | Required | Runtime behavior |
| --- | --- | --- |
| `PORT` | No | HTTP port; defaults to `5000`. |
| `DB_HOST` | Yes | PostgreSQL host or RDS endpoint. |
| `DB_USER` | Yes | PostgreSQL user. |
| `DB_PASSWORD` | Yes | PostgreSQL password. |
| `DB_NAME` | No | Defaults to `appdnb`; configure an existing database. |
| `DB_PORT` | No | Defaults to `5432`. |
| `NODE_ENV` | No | If `production`, enables PostgreSQL TLS with `rejectUnauthorized: false`. |

**Why this was done:** Connection settings come from environment variables, not source literals, so the same API image can be configured for different environments. The health endpoint is a process-level check; `/api/data` also exercises database connectivity.

Run the currently available backend checks from the repository root:

```bash
cd app/backend
npm install
node --check server.js
npm test --if-present
```

The frontend image can be built independently:

```bash
docker build -t electro-frontend ./app/frontend
```

The backend image build requires the absent `package-lock.json`; it will not succeed with `npm ci` until a lockfile is added.

### 1.4 Database — RDS PostgreSQL

`modules/rds/main.tf` provisions the RDS instance. Its configured engine is PostgreSQL `16.3`, class `db.t3.medium`, with `20` GB initial `gp3` storage and `100` GB maximum autoscaling storage. It uses the supplied subnet group and security-group IDs, is not publicly accessible, and is single-AZ.

Relevant configuration excerpt:

```hcl
resource "aws_db_instance" "db" {
  identifier           = var.identifier
  engine               = "postgres"
  engine_version       = "16.3"
  instance_class       = var.instance_class

  username               = var.db_username
  password               = var.db_password
  allocated_storage      = var.allocated_storage
  max_allocated_storage  = var.max_allocated_storage
  storage_type           = "gp3"

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  monitoring_interval                   = 0
  multi_az = false
}
```

**Why this was done:** RDS is placed in private subnets to avoid direct public reachability, while the application tier connects through the VPC. The current module enables Performance Insights, but does not configure Enhanced Monitoring or explicitly set `storage_encrypted`.

### 1.5 Container image practices

`app/backend/Dockerfile` uses two Node Alpine stages and drops privileges in the runtime stage:

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

**Best practices present:** multi-stage build, minimal Alpine base, production dependency installation, non-root `USER node`, and ownership-correct copies.

> **Build blocker:** `npm ci` requires a lockfile, but `app/backend/` currently has no `package-lock.json`. Generate and commit the lockfile before relying on this Docker build.

**Why this was done:** Multi-stage builds avoid carrying build-only content into runtime, Alpine reduces base-image size, and running as `node` limits the impact of a compromised application process.

---

<div style="page-break-after: always;"></div>

## Step 2 — Infrastructure Provisioning with Terraform

### 2.1 Repository layout and module responsibilities

Reusable modules are in the repository-root `modules/` directory. Environment stacks live in `environment/production/` and use separate S3 remote-state keys. Terraform requires `>= 1.13.0`, AWS provider `6.28.0`, and region `us-east-1`.

| Module / layer | What it provisions | Present configuration |
| --- | --- | --- |
| `modules/vpc` | VPC, public/private subnets, Internet Gateway, NAT Gateway, Elastic IP, route tables, and associations. | VPC `10.0.0.0/16`; public `10.0.1.0/24`, `10.0.2.0/24`; private `10.0.3.0/24`, `10.0.4.0/24`; DNS hostnames enabled. |
| `modules/rds` | DB subnet group and PostgreSQL RDS instance. | PostgreSQL `16.3`; `db.t3.medium`; `20` GB `gp3`, autoscaling max `100` GB; private and single-AZ; Performance Insights retention `7` days. |
| `modules/ec2` | Ubuntu 24.04 EC2 instance with subnet, security group, optional instance profile, key pair, and `gp3` root volume. | `ec2_layer` creates `Bastion_Host`, `Application_Tier`, and `Web_Tier`; its tfvars use `t3.micro`, key name `7ader`, and a 20 GB root volume. |
| `environment/production/permission_layer` | Security groups, IAM role, and instance profile for private EC2. | Role attaches SSM managed core, ECR read-only, EC2 read-only, and RDS full-access AWS managed policies. |
| **ECS** | No module or ECS task/service configuration exists in this repository. | The application workflow deployment target is EC2. |
| **ECR** | No Terraform ECR module/repository resource exists in this repository. | App workflows refer to pre-existing repositories `electro_backend` and `electro_frontend`. |

Layer state is kept in S3 bucket `electro-terraform`, region `us-east-1`: `vpc/terraform.tfstate`, `permission/terraform.tfstate`, `ec2/terraform.tfstate`, and `rds/terraform.tfstate`. The backend bucket must already exist and is not created by these stacks.

**Why this was done:** Separate modules support reuse, and separate layer state files express dependencies through remote state. The available modules reflect the infrastructure that is actually implemented; ECS and ECR are not silently assumed to exist as Terraform resources.

### 2.2 Security posture — configured behavior and gaps

> **Important:** The request describes private subnets, least-privilege security groups, and encryption at rest as target controls. Only private RDS placement is currently configured. Review and correct the security-group rules and encryption settings before production use.

| Control | Repository configuration |
| --- | --- |
| RDS public exposure | `publicly_accessible = false`; subnet IDs are sourced from the VPC private subnets. |
| EC2 private security group | Allows all protocols from `0.0.0.0/0` inbound. This is not least-privilege. |
| Public security group | Allows SSH `22` from `0.0.0.0/0`, all-protocol ingress from `0.0.0.0/0`, and HTTP `80` / HTTPS `443` from `0.0.0.0/0`. |
| RDS security group | Allows TCP `1433` from `0.0.0.0/0`. PostgreSQL commonly listens on `5432`, so this does not match the application's default port and should be reviewed. |
| Encryption at rest | `storage_encrypted` is not set by the RDS module. Encryption is not explicitly configured in code. |
| Monitoring | Performance Insights enabled for 7 days; Enhanced Monitoring disabled with `monitoring_interval = 0`; no CloudWatch alarm resources are defined. |
| IAM permissions | The EC2 role includes `AmazonRDSFullAccess` and other AWS managed policies; review whether narrower permissions can be used. |
| Terraform secrets/state | DB username/password variables are marked `sensitive`; sensitive values may still be stored in Terraform state. Protect the S3 bucket and access. |

### 2.3 Manual Terraform procedure

**Prerequisites:** Terraform `1.13` or later, authorized AWS credentials, existing S3 backend bucket `electro-terraform` in `us-east-1`, and the EC2 key pair referenced in `environment/production/ec2_layer/terraform.tfvars`. The production RDS layer requires `TF_VAR_db_username` and `TF_VAR_db_password`.

> **Credential callout:** Use an AWS profile and prompt for the RDS password. Do not place credentials in source files or commit Terraform state.

```bash
export AWS_PROFILE=your-aws-profile
read -r -p "RDS username: " TF_VAR_db_username
read -r -s -p "RDS password: " TF_VAR_db_password
printf '\n'
export TF_VAR_db_username TF_VAR_db_password
```

Initialize, validate, plan, and apply each layer in dependency order. Review the generated plan before applying:

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

**Why this was done:** Applying VPC first makes its remote-state outputs available to permission, EC2, and RDS layers. Applying resources incurs AWS charges. The repository's manually dispatched `.github/workflows/destroy_ifra_prod.yml` destroys layers in reverse order; use teardown only when intentional.

---

<div style="page-break-after: always;"></div>

## Step 3 — Local Orchestration with Docker Compose

### 3.1 Current Compose status

The tracked `app/docker_compose.yml` is currently **zero bytes**. It defines no database, backend, or frontend services, so the complete three-tier stack cannot currently be started or tested using Compose. A working file would need to define:

| Service | Minimum required configuration |
| --- | --- |
| **Frontend** | Build from `app/frontend`, publish port `80`, and share a Docker network with a service resolvable as `backend-api`. |
| **Backend** | Build from `app/backend`, listen on port `5000`, receive `DB_HOST`, `DB_USER`, `DB_PASSWORD`, optional `DB_NAME` and `DB_PORT`, and connect to the database service. |
| **PostgreSQL** | Database image, persistent storage, credentials supplied safely, and a health check/readiness condition if startup ordering is needed. |

**Why this was done:** Compose is intended to make multi-container development repeatable, but inventing service definitions here would misrepresent the checked-in project. The commands below become usable when the empty file is populated and the backend lockfile is added.

### 3.2 Compose start, logs, and troubleshooting commands

<div class="code-callout">

```bash
# From the repository root, after app/docker_compose.yml defines services:
docker compose -f app/docker_compose.yml config
docker compose -f app/docker_compose.yml build
docker compose -f app/docker_compose.yml up --detach
docker compose -f app/docker_compose.yml ps
docker compose -f app/docker_compose.yml logs --follow

# Inspect a single service and follow its logs:
docker compose -f app/docker_compose.yml logs --follow backend
docker compose -f app/docker_compose.yml logs --follow frontend
docker compose -f app/docker_compose.yml logs --follow db

# Recreate a service after changing its image/configuration:
docker compose -f app/docker_compose.yml up --detach --force-recreate backend

# Stop and remove the stack:
docker compose -f app/docker_compose.yml down
```

</div>

Because no `db` service is currently defined, the service-specific `db` log command is also conditional on adding a service with that name. If Compose reports a YAML/configuration error, run `docker compose -f app/docker_compose.yml config` after the file has been populated. If the API cannot reach PostgreSQL, verify `DB_HOST`, credentials, database name, port, and that the database is ready before the API starts.

### 3.3 Build and test the current code outside Compose

The backend's existing scripts are:

```bash
cd app/backend
npm install
node --check server.js
npm test --if-present
```

The backend test is the `node unit.js` script declared in `package.json`. It is a minimal runtime/assertion test, not an integration test of the Express routes or PostgreSQL. To exercise `/api/data`, the API must be running with valid DB environment variables and a reachable PostgreSQL server.

---

<div style="page-break-after: always;"></div>

## Step 4 — Automated CI/CD Pipeline (GitHub Actions & AWS ECR)

### 4.1 Implemented application workflow stages

The requested four-stage lifecycle maps to the repository as follows. The actual deploy target is **EC2, not ECS**:

| Stage | Backend — `backend_pipe.yml` | Frontend — `frontend_pipeline.yml` |
| --- | --- | --- |
| **1. Build / setup** | Checkout; set up Node.js `20`; run in `app/backend`. | Checkout repository. |
| **2. Test** | `npm install`, `node --check server.js`, `npm test --if-present`. | No frontend test stage is configured. |
| **3. Build & Push (ECR)** | Login to ECR; build and push `557496517532.dkr.ecr.us-east-1.amazonaws.com/electro_backend:v1.0.<run number>`. | Login to ECR; build and push `557496517532.dkr.ecr.us-east-1.amazonaws.com/electro_frontend:v1.0.<run number>`. |
| **4. Deploy** | Find running EC2 instance with tag `Name=Test`; SSH as `ubuntu`; update remote Compose image; pull and recreate `backend`. | Find running EC2 instance with tag `Name=Test`; SSH as `ubuntu`; update remote Compose image; pull and recreate `frontend`. |

The backend workflow triggers on pushes to `main` affecting `app/backend/**` or via `workflow_dispatch`. Its path filter names `.github/workflows/backend.yml`, but the actual workflow file is `backend_pipe.yml`. The frontend workflow triggers on pushes to `main` affecting `app/frontend/**` or via manual dispatch.

The deployment SSH commands operate on `/home/ubuntu/docker-compose.yml`, which is not this repository's `app/docker_compose.yml`. They run `docker compose pull <service>`, `docker compose up -d --no-deps --force-recreate <service>`, `docker image prune -f`, and list running containers. Terraform creates `Bastion_Host`, `Application_Tier`, and `Web_Tier`, while the app workflows search for `Name=Test`; align these resources and the remote Compose file before deployment.

The backend workflow's image publication commands are:

```bash
docker build -t "$REGISTRY/$REPO:$IMAGE_TAG" .
docker push "$REGISTRY/$REPO:$IMAGE_TAG"
```

The EC2 lookup used in both app workflows is:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=Test" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].PublicIpAddress" \
  --output text
```

**Why this was done:** The backend workflow gates image publication on syntax and test commands; both workflows use versioned image tags. ECR provides the image registry. The current SSH-based EC2 rollout is what the repository implements; it should not be described as an ECS deployment.

### 4.2 Infrastructure workflows

| Workflow | Trigger | Actions |
| --- | --- | --- |
| `.github/workflows/infra.yml` | Manual `workflow_dispatch`. | Configures AWS credentials for `us-east-1`, sets up Terraform `1.13`, then initializes, validates, plans, and applies VPC → permissions → EC2 → RDS. Passes DB credentials to the RDS layer as `TF_VAR_db_username` and `TF_VAR_db_password`. |
| `.github/workflows/destroy_ifra_prod.yml` | Manual `workflow_dispatch`. | Destroys RDS → EC2 → permissions → VPC. DB credentials are passed to the RDS layer. This is destructive; trigger only for intentional teardown. |

### 4.3 Secrets management

Configure these in **GitHub repository → Settings → Secrets and variables → Actions**. Workflow files reference credentials using `${{ secrets.NAME }}`; credential values are not embedded directly in those YAML files. Terraform state may still contain sensitive values, so secure remote state.

| Secret | Purpose | Required by |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | AWS access key for AWS API authentication. | Backend, frontend, infrastructure apply, infrastructure destroy. |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key paired with the access key. | Backend, frontend, infrastructure apply, infrastructure destroy. |
| `DB_USERNAME` | Passed as `TF_VAR_db_username` to Terraform. | Infrastructure apply and destroy, RDS layer. |
| `DB_PASSWORD` | Passed as `TF_VAR_db_password` to Terraform. | Infrastructure apply and destroy, RDS layer. |
| `EC2_SSH_KEY` | Private SSH key for remote container deployment. | Backend and frontend image workflows. |

**Why this was done:** GitHub Actions secrets avoid checking credential literals into workflow files. Use least-privilege IAM credentials, rotate secrets as needed, and restrict access to Terraform's S3 state bucket. Secret masking does not replace state protection.

---

<div style="page-break-after: always;"></div>

## Step 5 — Verification & Observability

### 5.1 API health and database checks

| Method | Endpoint | What it verifies | Sample response |
| --- | --- | --- | --- |
| `GET` | `/health` | Express process responds; this endpoint does not query the database. | `{"status":"healthy","timestamp":"<current timestamp>"}` |
| `GET` | `/api/data` | API can execute `SELECT NOW()` against PostgreSQL. On query failure, responds with HTTP `500`. | `{"message":"Hello from the Backend API!","db_time":"<database timestamp>"}` |

Run the API directly on port `5000`:

```bash
curl --fail --silent --show-error http://localhost:5000/health
curl --fail --silent --show-error http://localhost:5000/api/data
```

If Nginx is running on port `80`, verify the proxied route:

```bash
curl --fail --silent --show-error http://localhost/api/data
```

`/health` is not proxied by the current Nginx config. Test it at the backend listener unless the proxy config is deliberately extended.

**Why this was done:** A process health endpoint is useful for liveness checks, while the data endpoint verifies both API execution and the database path. They intentionally represent different health signals.

### 5.2 Logs, metrics, and alerting status

| Signal | Current implementation |
| --- | --- |
| API application logs | `console.log` reports the listening port; database query failures use `console.error`. In a container, these go to standard output/error and can be viewed with `docker compose logs` once the Compose stack exists. |
| CloudWatch logs | No Terraform CloudWatch log group or log-stream configuration is defined for the application. Do not assume application logs are currently shipped to CloudWatch. |
| RDS Performance Insights | Enabled with retention period `7` days. |
| RDS Enhanced Monitoring | Disabled (`monitoring_interval = 0`). |
| High-CPU alert | No CloudWatch alarm or high-CPU metric alarm resource is configured in the repository. |

Example local log/health checks, once the Compose services exist:

```bash
docker compose -f app/docker_compose.yml ps
docker compose -f app/docker_compose.yml logs --tail=100 backend
docker compose -f app/docker_compose.yml logs --tail=100 frontend
curl --fail --silent --show-error http://localhost:5000/health
curl --fail --silent --show-error http://localhost:5000/api/data
```

**Why this was done:** Logs and health checks make failures diagnosable, but they only provide the signals actually wired into the system. Before relying on AWS observability, provision log delivery and alert rules; the guide does not claim a high-CPU alert exists.

---

## PDF export notes

This Markdown uses explicit section breaks and collapsible details for browser readability. For PDF output, review the generated pages because HTML page-break styling is renderer-dependent. One Pandoc option is:

```bash
pandoc README.md --from gfm+raw_html --output 3-tier-application-guide.pdf --pdf-engine=xelatex
```

The export host must have Pandoc and a supported LaTeX engine installed. GitHub-compatible Markdown renders the source as a technical guide; the PDF command is an optional local export path.

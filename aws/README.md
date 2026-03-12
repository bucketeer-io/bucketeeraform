# Bucketeer on AWS (Terraform)

ECS Fargate + RDS MySQL + ElastiCache Redis. No PostgreSQL.

## Layout

- **aws/modules/** — Terraform (VPC, RDS, ElastiCache, ECS, ALB, ECR).
- **aws/terraform-config/** — Copy `config.tfvars.template` → `config.tfvars`, set `db_password` and AWS keys. Do not commit `config.tfvars`.

## Quick start

```bash
make init-aws
make plan-aws
make apply-aws
```

Then run **`make push-aws`** to build images (with config) and push to ECR. Otherwise ECS will fail with `CannotPullContainerError`.

Then run **`make migrate-aws`** to apply DB migrations (runs pre-migration fix, then Atlas; on first failure retries once after re-running the fix).

## Migration

- **`make migrate-aws`** — Runs pre-migration SQL (fixes nullable `environment_id` for Atlas), then Atlas migrate. If the migration fails at the INPLACE step, it runs the pre-migration fix again and retries once.
- Ensure **`make push-aws`** has been run before deploying so all service images (including subscriber) exist in ECR.

## Subscriber and Redis

Subscriber uses the same VPC and ECS security group as other services; Redis (ElastiCache) allows ingress from the ECS security group on port 6379. If the subscriber cannot reach Redis:

1. Ensure **`make push-aws`** has been run so the subscriber image exists (otherwise the task fails with `CannotPullContainerError`).
2. Force a new deployment after push: ECS → subscriber service → Update → Force new deployment.
3. Check CloudWatch log group `/ecs/bucketeer`, stream prefix `subscriber/`, for the exact error.

## Config and services

- **config/** (repo root) — Config files baked into images. Same layout as before: `config/oauth-config.json`, `config/email-config.json`, `config/datawarehouse.yaml`, `config/nginx/`, `config/subscriber-config/`, `config/batch-jobs/`.
- **services/** — Dockerfiles and entrypoints per service (api, web, batch, nginx, subscriber, batch-cron). Used by both Fly (`push-images.sh`) and AWS (`push-aws`).

**`make push-aws`** builds from **services/** Dockerfiles with repo root as context, so **config/** is copied into the images, then pushes to ECR. No docker-compose folder required.

## Fix: CannotPullContainerError

Run **`make push-aws`** from repo root. It builds the four images from services/ (with config/) and pushes to ECR. Then in ECS: each service → Update → Force new deployment.

## Variables

Set in `aws/terraform-config/config.tfvars`. See `config.tfvars.template`. Required: `aws_region`, `app_name`, `db_password`; optional: `aws_access_key_id`, `aws_secret_access_key` (omit to use env/CLI).

## Query database from AWS Console

RDS is set `publicly_accessible = true` and the RDS security group allows inbound MySQL (3306) from the internet so you can use **RDS Query Editor** (or any MySQL client):

1. In AWS Console go to **RDS** → **Databases** → select your DB → copy the **Endpoint**.
2. Go to **RDS** → **Query Editor** (or **Query Editor v2**), create a connection:
   - **Endpoint**: from step 1
   - **Port**: 3306
   - **User** / **Password**: same as in `config.tfvars` (`db_username`, `db_password`)
   - **Database**: `bucketeer` (or your `db_name`)

For production, restrict the RDS security group (e.g. allow only your IP or a bastion) instead of `0.0.0.0/0`.

## Destroy

```bash
make destroy-aws
```

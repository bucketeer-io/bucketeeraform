APP_PREFIX   ?= bucketeer

export FLYCTL_NO_UPDATE_CHECK := 1
export FLY_NO_UPDATE_CHECK := 1

# ── Fly.io (fly.toml based) ───────────────────────────────────────────────────

create-redis-flyio:
	@. flyio/config.env && \
	REDIS_DB="$${APP_PREFIX}-redis" && \
	if fly redis list 2>/dev/null | grep -q "$$REDIS_DB"; then \
		echo "Upstash Redis '$$REDIS_DB' already exists"; \
		fly redis status "$$REDIS_DB"; \
	else \
		echo "Creating Upstash Redis '$$REDIS_DB'..." && \
		fly redis create --name "$$REDIS_DB" --region "$${REGION}" --no-replicas --disable-eviction --enable-prodpack=false --plan "Pay-as-you-go" -o personal; \
	fi

gen-certs-flyio:
	@echo "Generating TLS cert with Fly.io .internal SANs..."
	@openssl req -x509 -nodes -newkey rsa:2048 \
		-keyout certs/tls.key -out certs/tls.crt \
		-days 36500 -subj "/CN=*.bucketeer.io" \
		-addext "subjectAltName=DNS:localhost,DNS:*.bucketeer.io,DNS:*.default.svc.cluster.local,DNS:*.bucketeer.local,DNS:nginx,DNS:web,DNS:api,DNS:batch,DNS:subscriber,DNS:mysql,DNS:redis,DNS:bucketeer-web.internal,DNS:bucketeer-nginx.internal,DNS:bucketeer-api.internal,DNS:bucketeer-batch.internal,DNS:bucketeer-subscriber.internal,DNS:bucketeer-mysql.internal"
	@echo "Done. SANs:" && openssl x509 -in certs/tls.crt -noout -ext subjectAltName

deploy-flyio: gen-certs-flyio create-redis-flyio
	bash flyio/deploy.sh

destroy-flyio:
	@export FLYCTL_NO_UPDATE_CHECK=1 && export FLY_NO_UPDATE_CHECK=1 && \
	. flyio/config.env && \
	for svc in batch-cron nginx subscriber batch api web migration httpstan mysql; do \
		echo "Destroying $${APP_PREFIX}-$${svc}..." && \
		fly app destroy "$${APP_PREFIX}-$${svc}" --yes 2>/dev/null || true; \
	done && \
	REDIS_DB="$${APP_PREFIX}-redis" && \
	if fly redis list 2>/dev/null | grep -q "$$REDIS_DB"; then \
		echo "Destroying Upstash Redis $${REDIS_DB}..." && \
		fly redis destroy "$$REDIS_DB" --yes 2>/dev/null || true; \
	fi

ip-flyio:
	@. flyio/config.env && \
	echo "==> Nginx (web console):" && fly ips list -a "$${APP_PREFIX}-nginx" && \
	echo "" && echo "==> API (global, SDK endpoint):" && fly ips list -a "$${APP_PREFIX}-api"

logs-flyio:
	@. flyio/config.env && fly logs -a "$${APP_PREFIX}-web"

# ── AWS ECS ───────────────────────────────────────────────────────────────────

init-aws:
	cd aws/modules && terraform init

plan-aws:
	cd aws/modules && terraform plan -var-file=../../aws/terraform-config/config.tfvars

apply-aws:
	cd aws/modules && terraform apply -var-file=../../aws/terraform-config/config.tfvars

push-aws:
	bash aws/push-ecr.sh

# Force new deployment of all ECS services (picks up new images after push-aws)
deploy-aws:
	@CLUSTER=$$(cd aws/modules && terraform output -raw ecs_cluster_name) && \
	REGION="$${AWS_REGION:-us-east-1}" && \
	for svc in nginx api web batch subscriber; do \
		echo "Forcing new deployment: bucketeer-$$svc" && \
		aws ecs update-service --cluster "$$CLUSTER" --service "bucketeer-$$svc" --force-new-deployment --region "$$REGION" --no-cli-pager --query 'service.serviceName' --output text || true; \
	done && \
	echo "Deployments triggered. New tasks will pull the latest image."

pre-migrate-aws:
	@echo "Running pre-migration SQL fix..."
	@CLUSTER=$$(cd aws/modules && terraform output -raw ecs_cluster_name) && \
	TASK_DEF=$$(cd aws/modules && terraform output -raw pre_migration_task_definition_arn) && \
	SUBNETS=$$(cd aws/modules && terraform output -raw ecs_subnet_ids) && \
	SG=$$(cd aws/modules && terraform output -raw ecs_security_group_id) && \
	TASK_ARN=$$(aws ecs run-task \
		--cluster "$$CLUSTER" \
		--task-definition "$$TASK_DEF" \
		--launch-type FARGATE \
		--network-configuration "awsvpcConfiguration={subnets=[$$SUBNETS],securityGroups=[$$SG],assignPublicIp=ENABLED}" \
		--query 'tasks[0].taskArn' \
		--output text) && \
	echo "Pre-migration task started: $$TASK_ARN" && \
	echo "Waiting for pre-migration to complete..." && \
	aws ecs wait tasks-stopped --cluster "$$CLUSTER" --tasks "$$TASK_ARN" && \
	EXIT_CODE=$$(aws ecs describe-tasks --cluster "$$CLUSTER" --tasks "$$TASK_ARN" \
		--query 'tasks[0].containers[0].exitCode' --output text) && \
	echo "Pre-migration finished with exit code $$EXIT_CODE (0 = success, non-zero may be OK if table doesn't exist yet)."

# Run Atlas migration; prints only container exit code to stdout (for migrate-aws to capture)
_run-migration:
	@CLUSTER=$$(cd aws/modules && terraform output -raw ecs_cluster_name) && \
	TASK_DEF=$$(cd aws/modules && terraform output -raw migration_task_definition_arn) && \
	SUBNETS=$$(cd aws/modules && terraform output -raw ecs_subnet_ids) && \
	SG=$$(cd aws/modules && terraform output -raw ecs_security_group_id) && \
	TASK_ARN=$$(aws ecs run-task \
		--cluster "$$CLUSTER" \
		--task-definition "$$TASK_DEF" \
		--launch-type FARGATE \
		--network-configuration "awsvpcConfiguration={subnets=[$$SUBNETS],securityGroups=[$$SG],assignPublicIp=ENABLED}" \
		--query 'tasks[0].taskArn' \
		--output text) && \
	echo "Migration task started: $$TASK_ARN" >&2 && \
	echo "Waiting for migration to complete..." >&2 && \
	aws ecs wait tasks-stopped --cluster "$$CLUSTER" --tasks "$$TASK_ARN" && \
	aws ecs describe-tasks --cluster "$$CLUSTER" --tasks "$$TASK_ARN" \
		--query 'tasks[0].containers[0].exitCode' --output text

migrate-aws: pre-migrate-aws
	@echo "Running database migration..."
	@EXIT_CODE=$$(make -s _run-migration); \
	if [ "$$EXIT_CODE" = "0" ]; then \
		echo "Migration completed successfully."; \
	elif [ "$$EXIT_CODE" = "1" ]; then \
		echo "Migration failed (exit 1). Running pre-migration fix and retrying once..."; \
		$(MAKE) -s pre-migrate-aws; \
		EXIT_CODE_2=$$(make -s _run-migration); \
		if [ "$$EXIT_CODE_2" = "0" ]; then echo "Migration completed on retry."; else echo "Migration failed on retry with exit code $$EXIT_CODE_2. Check CloudWatch logs."; exit 1; fi; \
	else \
		echo "Migration failed with exit code $$EXIT_CODE. Check CloudWatch logs."; \
		exit 1; \
	fi

destroy-aws:
	cd aws/modules && terraform destroy -var-file=../../aws/terraform-config/config.tfvars

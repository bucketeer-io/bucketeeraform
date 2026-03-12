APP_PREFIX   ?= bucketeer

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

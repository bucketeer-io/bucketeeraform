FROM alpine:3.22.1
RUN apk add --no-cache curl dcron ca-certificates
# Bundle cron config and batch job runner (config/ at repo root)
COPY config/batch-jobs/run-batch-job.sh /usr/local/bin/run-batch-job.sh
COPY config/batch-jobs/crontab          /etc/cron.d/bucketeer-batch
RUN chmod +x /usr/local/bin/run-batch-job.sh \
 && chmod 0644 /etc/cron.d/bucketeer-batch
COPY services/batch-cron/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

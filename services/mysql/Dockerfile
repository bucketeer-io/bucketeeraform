FROM mysql:8.0
COPY services/mysql/init-db/mysql_dump.sql /docker-entrypoint-initdb.d/
COPY config/mysql-conf/log_bin.cnf /etc/mysql/conf.d/log_bin.cnf
CMD ["--default-authentication-plugin=mysql_native_password", \
     "--character-set-server=utf8mb4", \
     "--collation-server=utf8mb4_general_ci", \
     "--log-bin-trust-function-creators=ON", \
     "--bind-address=::"]

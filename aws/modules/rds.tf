# RDS MySQL — free tier: db.t3.micro, single AZ, 20 GB

resource "aws_db_parameter_group" "mysql" {
  family = "mysql8.0"
  name   = "${local.name}-mysql"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_general_ci"
  }
}

resource "aws_db_instance" "main" {
  identifier     = local.name
  engine         = "mysql"
  engine_version = "8.0"

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp2"
  storage_encrypted = false # set true for production

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true # allow RDS Query Editor and clients from internet (restrict SG in production)
  multi_az               = false

  parameter_group_name = aws_db_parameter_group.mysql.name
  skip_final_snapshot  = true

  tags = {
    Name = local.name
  }
}

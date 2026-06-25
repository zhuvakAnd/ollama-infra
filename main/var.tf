variable "db_username" {
  description = "Master DB username"
  type        = string
  default     = "postgres"
}

variable "alert_email" {
  description = "Email address for health monitoring SNS alerts"
  type        = string
  default     = "zhuvak.andrii@gmail.com"
}

variable "db_connections_threshold" {
  description = "Maximum RDS connections before CloudWatch alarm fires"
  type        = number
  default     = 80
}

variable "db_size_threshold_gb" {
  description = "Maximum RDS database size in GB before CloudWatch alarm fires"
  type        = number
  default     = 15
}

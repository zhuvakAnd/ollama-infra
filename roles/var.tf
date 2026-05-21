variable "github_repo" {
  description = "Full GitHub repository name (owner/repo) used as the pipeline source"
  type        = string
}

variable "approval_email" {
  description = "Email address to receive manual approval notifications (leave empty to skip subscription)"
  type        = string
  default     = ""
}

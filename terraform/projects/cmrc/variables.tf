variable "jfrog_url" {
  description = "Base URL of the JFrog Platform instance."
  type        = string
}

variable "jfrog_access_token" {
  description = "JFrog Platform access token. Pass via TF_VAR_jfrog_access_token."
  type        = string
  sensitive   = true
}

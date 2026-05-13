variable "jfrog_url" {
  description = "Base URL of the JFrog Platform instance."
  type        = string
}

variable "jfrog_access_token" {
  description = "JFrog Platform access token."
  type        = string
  sensitive   = true
}

variable "project_key" {
  description = "Project key these repos belong to. Must already exist (created by the platform layer)."
  type        = string
}

variable "repos_config_file" {
  description = "Path to repos.json for this project — contains the applications array."
  type        = string
}

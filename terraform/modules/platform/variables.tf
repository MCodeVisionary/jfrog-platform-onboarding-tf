variable "jfrog_url" {
  description = "Base URL of the JFrog Platform instance (e.g. https://myorg.jfrog.io)"
  type        = string
}

variable "jfrog_access_token" {
  description = "JFrog Platform access token."
  type        = string
  sensitive   = true
}

variable "projects_config_file" {
  description = "Path to the JSON file describing project metadata (no repo definitions)."
  type        = string
}

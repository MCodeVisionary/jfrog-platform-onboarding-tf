variable "jfrog_url" {
  description = "Base URL of the JFrog Platform instance."
  type        = string
}

variable "jfrog_access_token" {
  description = "JFrog Platform access token. The identity behind it needs Xray Admin scope."
  type        = string
  sensitive   = true
}

variable "curation_policies_file" {
  description = "Path to the JSON file describing curation policies. Each entry maps to one xray_curation_policy resource. Unset / empty string = manage zero policies."
  type        = string
  default     = ""
}

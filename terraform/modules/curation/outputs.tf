output "curation_policy_count" {
  description = "Number of Xray curation policies managed by this layer."
  value       = length(xray_curation_policy.this)
}

output "curation_policy_names" {
  description = "List of curation policy names managed by this layer."
  value       = sort([for k in keys(xray_curation_policy.this) : k])
}

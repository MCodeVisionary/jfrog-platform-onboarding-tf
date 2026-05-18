# ---------------------------------------------------------------------------
# Parse the curation policies JSON file. Fields beginning with "_" (e.g.
# "_comment", "_condition") are documentation-only and are stripped before
# being passed to the resource. Optional resource fields default to null
# so they only emit on the wire when the JSON explicitly sets them.
# ---------------------------------------------------------------------------
locals {
  curation_policies = (
    var.curation_policies_file == "" ? {} :
    {
      for p in jsondecode(file(var.curation_policies_file)).policies :
      p.name => {
        name                  = p.name
        condition_id          = tostring(p.condition_id)
        scope                 = lookup(p, "scope", "all_repos")
        policy_action         = lookup(p, "policy_action", "block")
        waiver_request_config = lookup(p, "waiver_request_config", "forbidden")
        repo_include          = lookup(p, "repo_include", null)
        repo_exclude          = lookup(p, "repo_exclude", null)
        pkg_types_include     = lookup(p, "pkg_types_include", null)
        notify_emails         = lookup(p, "notify_emails", null)
        decision_owners       = lookup(p, "decision_owners", null)
      }
    }
  )
}

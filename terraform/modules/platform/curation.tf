# ---------------------------------------------------------------------------
# Curation Policies — platform-wide (scope = all_repos by default).
#
# Driven entirely by local.curation_policies (parsed from
# var.curation_policies_file). Set the variable to "" or leave the JSON's
# policies array empty to manage zero policies — useful in dev / test
# environments where Curation isn't licensed.
#
# Each entry references a JFrog-side condition by ID. The condition itself
# (its risk_type, supported_pkg_types, on_demand flag, param_values, etc.)
# is managed by JFrog — we only declare the policy that USES it. See:
#   https://jfrog.com/help/r/jfrog-security-user-guide/products/curation/conditions
#
# All policies are block + forbidden waivers, matching the security posture
# encoded in platform/curation_policies.json.
# ---------------------------------------------------------------------------

resource "xray_curation_policy" "this" {
  for_each = local.curation_policies

  name                  = each.value.name
  condition_id          = each.value.condition_id
  scope                 = each.value.scope
  policy_action         = each.value.policy_action
  waiver_request_config = each.value.waiver_request_config

  # Optional fields only emit when the JSON sets them.
  repo_include      = each.value.repo_include
  repo_exclude      = each.value.repo_exclude
  pkg_types_include = each.value.pkg_types_include
  notify_emails     = each.value.notify_emails
  decision_owners   = each.value.decision_owners
}

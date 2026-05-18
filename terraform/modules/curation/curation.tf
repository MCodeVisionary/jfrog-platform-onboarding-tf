# ---------------------------------------------------------------------------
# Xray Curation Policies
#
# Each entry in local.curation_policies maps to one xray_curation_policy
# resource. Conditions themselves (their risk_type, supported_pkg_types,
# param_values, etc.) are managed by JFrog — we declare only the *policy*
# that USES a condition, referenced by condition_id. See:
#   https://jfrog.com/help/r/jfrog-security-user-guide/products/curation/conditions
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

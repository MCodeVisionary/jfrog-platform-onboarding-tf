# ---------------------------------------------------------------------------
# Parse project metadata. This layer ONLY knows about projects — repo
# definitions live in the per-project layer's repos.json.
# ---------------------------------------------------------------------------
locals {
  raw_config = jsondecode(file(var.projects_config_file))

  projects = {
    for display_name, proj in local.raw_config.projects : display_name => {
      key             = proj.key
      display_name    = proj.display_name
      description     = lookup(proj, "description", "")
      max_storage_gib = lookup(proj, "max_storage_gib", 500)
      uses_global     = contains(lookup(proj, "stages", ["all"]), "all")
      extra_stages    = [for s in lookup(proj, "stages", ["all"]) : s if s != "all"]
    }
  }

  # IDP group names per project — pattern: {ROLE}-{project-key}
  project_groups = {
    for _, proj in local.projects : proj.key => {
      admin = "ADMIN-${proj.key}"
      write = "WRITE-${proj.key}"
      read  = "READ-${proj.key}"
    }
  }

  # Group → role bindings flattened for project_group resources.
  # Each entry: { project_key, group_name, roles }
  project_role_bindings = flatten([
    for _, proj in local.projects : [
      { project_key = proj.key, group_name = local.project_groups[proj.key].admin, roles = ["Project Admin"] },
      { project_key = proj.key, group_name = local.project_groups[proj.key].write, roles = ["Developer"] },
      { project_key = proj.key, group_name = local.project_groups[proj.key].read, roles = ["Viewer"] },
      { project_key = proj.key, group_name = "security-admin", roles = ["Security Manager"] },
    ]
  ])

  # Global lifecycle stage names — inherited by every project.
  # Each per-project layer also generates *-{stage}-local repos for every
  # stage listed here (driven by stage_env_map in modules/project-repos).
  global_stage_names = ["DEV", "QA", "STG", "PROD"]

  # Per-project extra stages (e.g. UAT, STG) flattened for null_resource iteration
  project_extra_stages = {
    for combo in flatten([
      for _, proj in local.projects : [
        for stage in proj.extra_stages : {
          id          = "${proj.key}-${stage}"
          project_key = proj.key
          stage       = stage
        }
      ]
    ]) : combo.id => combo
  }

}

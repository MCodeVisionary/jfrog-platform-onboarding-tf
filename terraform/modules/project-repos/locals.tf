# ---------------------------------------------------------------------------
# Derive local/remote/virtual repo maps for one project from its repos.json.
# ---------------------------------------------------------------------------
locals {
  config       = jsondecode(file(var.repos_config_file))
  applications = local.config.applications

  # Deduplicated list of every package_type used across all this project's
  # applications — drives the one-remote-per-tech rule.
  all_techs = distinct(flatten([for app in local.applications : app.package_types]))

  # Upstream registry URLs per package type
  remote_upstream = {
    npm         = "https://registry.npmjs.org"
    python      = "https://pypi.org"
    terraform   = "https://registry.terraform.io"
    docker      = "https://registry-1.docker.io"
    helm        = "https://charts.helm.sh/stable"
    nuget       = "https://www.nuget.org/"
    maven       = "https://repo1.maven.org/maven2/"
    huggingface = "https://huggingface.co"
  }

  # package_types with no virtual repository type in the provider — excluded
  # from virtual_repos generation below.
  techs_without_virtual = ["huggingface"]

  # Stage suffix (used in repo keys) → JFrog environment label (used in
  # project_environments). Must match global_stage_names in modules/platform.
  stage_env_map = {
    dev  = "DEV"
    qa   = "QA"
    stg  = "STG"
    prod = "PROD"
  }

  # ---------------------------------------------------------------------------
  # LOCAL repositories
  # Pattern: {project-key}-{app}-{tech}-{stage}-local
  # ---------------------------------------------------------------------------
  local_repos = {
    for combo in flatten([
      for app in local.applications : [
        for tech in app.package_types : [
          for stage, env in local.stage_env_map : {
            id    = "${var.project_key}-${app.name}-${tech}-${stage}-local"
            app   = app.name
            tech  = tech
            stage = stage
            env   = env
          }
        ]
      ]
    ]) : combo.id => combo
  }

  local_repos_npm         = { for k, v in local.local_repos : k => v if v.tech == "npm" }
  local_repos_python      = { for k, v in local.local_repos : k => v if v.tech == "python" }
  local_repos_terraform   = { for k, v in local.local_repos : k => v if v.tech == "terraform" }
  local_repos_docker      = { for k, v in local.local_repos : k => v if v.tech == "docker" }
  local_repos_helm        = { for k, v in local.local_repos : k => v if v.tech == "helm" }
  local_repos_nuget       = { for k, v in local.local_repos : k => v if v.tech == "nuget" }
  local_repos_maven       = { for k, v in local.local_repos : k => v if v.tech == "maven" }
  local_repos_huggingface = { for k, v in local.local_repos : k => v if v.tech == "huggingface" }

  # ---------------------------------------------------------------------------
  # REMOTE repositories
  # Pattern: {project-key}-{tech}-remote — one per tech used by this project.
  # ---------------------------------------------------------------------------
  remote_repos = {
    for tech in local.all_techs :
    "${var.project_key}-${tech}-remote" => {
      tech = tech
      url  = local.remote_upstream[tech]
    }
  }

  remote_repos_npm         = { for k, v in local.remote_repos : k => v if v.tech == "npm" }
  remote_repos_python      = { for k, v in local.remote_repos : k => v if v.tech == "python" }
  remote_repos_terraform   = { for k, v in local.remote_repos : k => v if v.tech == "terraform" }
  remote_repos_docker      = { for k, v in local.remote_repos : k => v if v.tech == "docker" }
  remote_repos_helm        = { for k, v in local.remote_repos : k => v if v.tech == "helm" }
  remote_repos_nuget       = { for k, v in local.remote_repos : k => v if v.tech == "nuget" }
  remote_repos_maven       = { for k, v in local.remote_repos : k => v if v.tech == "maven" }
  remote_repos_huggingface = { for k, v in local.remote_repos : k => v if v.tech == "huggingface" }

  # ---------------------------------------------------------------------------
  # VIRTUAL repositories — DEV stage only
  # Pattern: {project-key}-{app}-{tech}-dev-virtual
  # ---------------------------------------------------------------------------
  virtual_repos = {
    for combo in flatten([
      for app in local.applications : [
        for tech in app.package_types : {
          id              = "${var.project_key}-${app.name}-${tech}-dev-virtual"
          app             = app.name
          tech            = tech
          stage           = "dev"
          env             = "DEV"
          local_repo_key  = "${var.project_key}-${app.name}-${tech}-dev-local"
          remote_repo_key = "${var.project_key}-${tech}-remote"
        } if !contains(local.techs_without_virtual, tech)
      ]
    ]) : combo.id => combo
  }

  virtual_repos_npm       = { for k, v in local.virtual_repos : k => v if v.tech == "npm" }
  virtual_repos_python    = { for k, v in local.virtual_repos : k => v if v.tech == "python" }
  virtual_repos_terraform = { for k, v in local.virtual_repos : k => v if v.tech == "terraform" }
  virtual_repos_docker    = { for k, v in local.virtual_repos : k => v if v.tech == "docker" }
  virtual_repos_helm      = { for k, v in local.virtual_repos : k => v if v.tech == "helm" }
  virtual_repos_nuget     = { for k, v in local.virtual_repos : k => v if v.tech == "nuget" }
  virtual_repos_maven     = { for k, v in local.virtual_repos : k => v if v.tech == "maven" }
}

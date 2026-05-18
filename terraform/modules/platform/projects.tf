# ---------------------------------------------------------------------------
# JFrog Projects — one per entry in projects.json.
# Repos are owned by the project-repos module (a separate state).
# ---------------------------------------------------------------------------

resource "project" "this" {
  for_each = local.projects

  key          = each.value.key
  display_name = each.value.display_name
  description  = each.value.description

  admin_privileges {
    manage_members   = true
    manage_resources = true
    index_resources  = true
  }

  max_storage_in_gibibytes   = each.value.max_storage_gib
  block_deployments_on_limit = false
  email_notification         = true

  depends_on = [
    null_resource.global_stages,
    platform_group.admin,
    platform_group.write,
    platform_group.read,
    platform_group.security_admin,
  ]
}

# ---------------------------------------------------------------------------
# Project-specific stages (non-"all" entries in a project's stages array)
# ---------------------------------------------------------------------------

resource "null_resource" "project_stages" {
  for_each = local.project_extra_stages

  triggers = {
    project_key = each.value.project_key
    stage       = each.value.stage
    jfrog_url   = var.jfrog_url
  }

  provisioner "local-exec" {
    command = <<-SCRIPT
      STAGE="${each.value.stage}"
      PROJECT="${each.value.project_key}"
      URL="${var.jfrog_url}"
      TOKEN="${var.jfrog_access_token}"

      echo "Checking project-specific stage: $STAGE for project $PROJECT"

      LIST=$(curl -s -H "Authorization: Bearer $TOKEN" \
        "$URL/access/api/v1/projects/$PROJECT/environments")

      # JFrog requires project-specific environment names to be prefixed with
      # the project key (e.g. "wlt-UAT"). We accept the un-prefixed stage in
      # config and add the prefix when creating.
      FULL_NAME="$PROJECT-$STAGE"
      if echo "$LIST" | grep -q "\"name\":\"$FULL_NAME\""; then
        echo "  Stage $FULL_NAME already exists for project $PROJECT — skipping."
      else
        echo "  Creating project-specific stage $FULL_NAME for $PROJECT..."
        HTTP=$(curl -s -o /tmp/proj_stage_response.json -w "%%{http_code}" \
          -X POST \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"name\":\"$FULL_NAME\"}" \
          "$URL/access/api/v1/projects/$PROJECT/environments")

        if [ "$HTTP" = "200" ] || [ "$HTTP" = "201" ] || [ "$HTTP" = "204" ] || [ "$HTTP" = "409" ]; then
          echo "  Stage $STAGE created for $PROJECT (HTTP $HTTP)."
        else
          echo "  ERROR: Failed to create stage $STAGE (HTTP $HTTP)"
          cat /tmp/proj_stage_response.json
          exit 1
        fi
      fi
    SCRIPT
  }

  depends_on = [project.this]
}

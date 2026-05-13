# ---------------------------------------------------------------------------
# Global Lifecycle Stages — DEV, QA, PROD
# Idempotent: list current envs, only POST if missing.
# ---------------------------------------------------------------------------

resource "null_resource" "global_stages" {
  for_each = toset(local.global_stage_names)

  triggers = {
    stage_name = each.key
    jfrog_url  = var.jfrog_url
  }

  provisioner "local-exec" {
    command = <<-SCRIPT
      STAGE="${each.key}"
      URL="${var.jfrog_url}"
      TOKEN="${var.jfrog_access_token}"

      echo "Checking stage: $STAGE"

      LIST=$(curl -s -H "Authorization: Bearer $TOKEN" \
        "$URL/access/api/v1/environments")

      if echo "$LIST" | grep -q "\"name\":\"$STAGE\""; then
        echo "  Stage $STAGE already exists — skipping."
      else
        echo "  Stage $STAGE not found — creating..."
        HTTP=$(curl -s -o /tmp/stage_create_response.json -w "%%{http_code}" \
          -X POST \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"name\":\"$STAGE\"}" \
          "$URL/access/api/v1/environments")

        if [ "$HTTP" = "200" ] || [ "$HTTP" = "201" ] || [ "$HTTP" = "204" ] || [ "$HTTP" = "409" ]; then
          echo "  Stage $STAGE created (HTTP $HTTP)."
        else
          echo "  ERROR: Failed to create stage $STAGE (HTTP $HTTP)"
          cat /tmp/stage_create_response.json
          exit 1
        fi
      fi
    SCRIPT
  }
}

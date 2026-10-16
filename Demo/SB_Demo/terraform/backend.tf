# ============================================================================
# State backend — local by default, remote when you need shared/portable state
# ============================================================================
# Terraform cannot switch backend *types* with variables (backends are static
# config), so this repository ships the zero-friction default — local state —
# with the remote block ready to uncomment. Pick one:
#
# A) LOCAL (default, works out of the box, state lives next to this file):
#      terraform init
#    The state file (*.tfstate) is git-ignored; copy it along with the repo or
#    bootstrap with `terraform import` on a fresh machine.
#
# B) REMOTE (shared S3-compatible state — AWS S3, Cloudflare R2, MinIO, ...):
#      1. cp backend.hcl.example backend.hcl   # fill in bucket/region/key
#      2. uncomment the backend "s3" block below
#      3. terraform init -backend-config=backend.hcl -reconfigure
#         (add -migrate-state to upload the existing local state)
#      4. terraform plan   # must report "No changes"
#    backend.hcl is git-ignored (environment-specific config, may embed
#    endpoints/credentials for private stores).
#
# Notes:
#  * There is no official Snowflake Terraform backend; S3-compatible object
#    storage is the portable standard for shared state.
#  * backend.hcl keeps bucket/key/region out of git, so the same configuration
#    works unchanged on every machine.
# ============================================================================

# terraform {
#   backend "s3" {
#     # All values are supplied via: terraform init -backend-config=backend.hcl
#     # bucket = ...  key = ...  region = ...   (see backend.hcl.example)
#     encrypt = true
#   }
# }

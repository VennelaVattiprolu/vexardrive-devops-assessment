# Identity used by GitHub Actions to deploy - NOT the same identity as
# azurerm_user_assigned_identity.app in identity.tf, which is the
# *runtime* identity the app itself uses to read Key Vault/pull from ACR.
# Separating these means a compromised CI pipeline and a compromised
# running app have different, independently-scoped blast radii.
#
# Was: the original GitHub Actions workflow authenticated to ACR with a
# long-lived admin username/password stored as a GitHub secret
# (`ACR_PASSWORD`). This identity replaces that entirely - GitHub's OIDC
# token is exchanged for a short-lived Azure AD token, so there is no
# credential to leak, rotate, or accidentally commit.
resource "azurerm_user_assigned_identity" "cicd" {
  name                = "${local.name_prefix}-cicd-identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}

# Federated credential trusts GitHub's OIDC issuer, but ONLY for workflow
# runs against THIS specific GitHub environment (dev/staging/prod) in
# THIS specific repo. A workflow run targeting the "dev" GitHub
# Environment can obtain a token for the dev identity/resource group -
# it cannot use this to reach into prod, since prod's identity has its
# own separate federated credential scoped to prod's own subject.
resource "azurerm_federated_identity_credential" "cicd_github" {
  name                = "${local.name_prefix}-github-oidc"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.cicd.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"

  # Update "VennelaVattiprolu/vexardrive-devops-assessment" if the repo
  # path differs. This subject format scopes the credential to runs
  # against this specific GitHub Environment - see
  # https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
  subject = "repo:VennelaVattiprolu/vexardrive-devops-assessment:environment:${var.environment}"
}

# Scoped permissions - only what the pipeline actually needs to do its job:
# push images and update the running Container App. Notably NOT
# "Contributor" on the whole resource group, which would also let CI
# modify/delete the database, Key Vault, networking, etc.
resource "azurerm_role_assignment" "cicd_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.cicd.principal_id
}

resource "azurerm_role_assignment" "cicd_container_apps" {
  scope                = azurerm_container_app.main.id
  role_definition_name = "Container Apps Contributor"
  principal_id         = azurerm_user_assigned_identity.cicd.principal_id
}

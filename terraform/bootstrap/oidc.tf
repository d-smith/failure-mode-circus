resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  # GitHub's OIDC token-signing certificate thumbprints. AWS validates the
  # connection against its own trusted CA store for this provider, but the
  # argument is still required; both current and prior intermediate CA
  # thumbprints are listed so rotation doesn't require a Terraform change.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider, referenced by github-oidc-role module instantiations in hub and scenario root modules."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

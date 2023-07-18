module "eks_blueprints_app_teams" {
  source  = "aws-ia/eks-blueprints-teams/aws"
  version = "~> 0.2"

  name = "data-team-a"

  users             = [data.aws_caller_identity.current.arn]
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn

  namespaces = {
    "data-team-a" = {
      labels = {
        "appName"     = "data-team-app",
        "projectName" = "project-teamA",
        "environment" = "dev"
      }
      resource_quota = {
        hard = {
          "pods"     = "10",
          "secrets"  = "10",
          "services" = "10"
        }
      }
    }
  }
}
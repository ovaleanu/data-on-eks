#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.14"
  role_name_prefix      = format("%s-%s-", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

module "eks_blueprints_kubernetes_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------------------------------
  # EKS Addons

  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
    vpc-cni = {
      preserve = true
    }
  }

  #---------------------------------------------------------------
  # Metrics Server
  #---------------------------------------------------------------
  enable_metrics_server = true

  #---------------------------------------------------------------
  # Cluster Autoscaler
  #---------------------------------------------------------------
  enable_cluster_autoscaler = true

  #---------------------------------------------------------------
  # Argo Events Add-on
  #---------------------------------------------------------------
  enable_argo_workflows = true

  #---------------------------------------
  # Prommetheus and Grafana stack
  #---------------------------------------
  #---------------------------------------------------------------
  # Install Kafka Montoring Stack with Prometheus and Grafana
  # 1- Grafana port-forward `kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack`
  # 2- Grafana Admin user: admin
  # 3- Get admin user password: `aws secretsmanager get-secret-value --secret-id <output.grafana_secret_name> --region $AWS_REGION --query "SecretString" --output text`
  #---------------------------------------------------------------
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [templatefile("${path.module}/helm-values/prom-grafana-values.yaml", {})]
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ],
    set = var.enable_amazon_prometheus ? [
      {
        name  = "prometheus.serviceAccount.name"
        value = local.amp_ingest_service_account
      },
      {
        name  = "prometheus.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
        value = module.amp_ingest_irsa[0].iam_role_arn
      },
      {
        name  = "prometheus.prometheusSpec.remoteWrite[0].url"
        value = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
      },
      {
        name  = "prometheus.prometheusSpec.remoteWrite[0].sigv4.region"
        value = local.region
      }
    ] : []
  }

  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    create            = true
    use_name_prefix   = false
    name              = "/${local.name}/aws-fluentbit-logs" # Add-on creates this log group
    retention_in_days = 30
  }
  aws_for_fluentbit = {
    create_namespace = true
    namespace        = "aws-for-fluentbit"
    create_role      = true
    role_policies    = { "policy1" = aws_iam_policy.fluentbit.arn }
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region               = local.region,
      cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
      s3_bucket_name       = module.fluentbit_s3_bucket.s3_bucket_id
      cluster_name         = module.eks.cluster_name
    })]
  }
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
# NOTE: This module will be moved to a dedicated repo and the source will be changed accordingly.
module "kubernetes_data_addons" {
  # Please note that local source will be replaced once the below repo is public
  # source = "https://github.com/aws-ia/terraform-aws-kubernetes-data-addons"
  source            = "../../../workshop/modules/terraform-aws-eks-data-addons"
  oidc_provider_arn = module.eks.oidc_provider_arn


  #---------------------------------------------------------------
  # Spark Operator Add-on
  #---------------------------------------------------------------
  enable_spark_operator = true
  spark_operator_helm_config = {
    values = [templatefile("${path.module}/helm-values/spark-operator-values.yaml", {})]
  }

  #---------------------------------------------------------------
  # Apache YuniKorn Add-on
  #---------------------------------------------------------------
  enable_yunikorn = true
  yunikorn_helm_config = {
    values = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {
      image_version = "1.2.0"
    })]
  }
}

#---------------------------------------------------------------
# Kubernetes Cluster role for argo workflows to run spark jobs
#---------------------------------------------------------------
resource "kubernetes_cluster_role" "spark_op_role" {
  metadata {
    name = "spark-op-role"
  }

  rule {
    verbs      = ["*"]
    api_groups = ["sparkoperator.k8s.io"]
    resources  = ["sparkapplications"]
  }
}
#---------------------------------------------------------------
# Kubernetes Role binding role for argo workflows/data-team-a
#---------------------------------------------------------------
resource "kubernetes_role_binding" "spark_role_binding" {
  metadata {
    name      = "data-team-a-spark-rolebinding"
    namespace = "data-team-a"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "argo-workflows"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.spark_op_role.id
  }
}
resource "kubernetes_role_binding" "admin_rolebinding_argoworkflows" {
  metadata {
    name      = "argo-workflows-admin-rolebinding"
    namespace = "argo-workflows"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "argo-workflows"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
}
resource "kubernetes_role_binding" "admin_rolebinding_data_teama" {
  metadata {
    name      = "data-team-a-admin-rolebinding"
    namespace = "data-team-a"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "data-team-a"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
}

#---------------------------------------------------------------
# IRSA for Argo events to read SQS
#---------------------------------------------------------------

module "irsa_argo_events" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.32.1"

  create_kubernetes_namespace = true
  kubernetes_namespace        = "argo-events"
  kubernetes_service_account  = "event-sa"
  irsa_iam_policies           = [data.aws_iam_policy.sqs.arn]
  eks_cluster_id              = module.eks.cluster_name
  eks_oidc_provider_arn       = module.eks.oidc_provider_arn
}

data "aws_iam_policy" "sqs" {
  name = "AmazonSQSReadOnlyAccess"
}

#locals {
#  event_namespace = "argo-events"
#  event_service_account = "event-sa"
#}

#resource "kubernetes_namespace_v1" "argo_events" {
#  metadata {
#    name = local.event_namespace
#  }
#  depends_on = [module.eks.cluster_name]
#}

#resource "kubernetes_service_account_v1" "event_sa" {
#  metadata {
#    name        = local.event_service_account
#    namespace   = kubernetes_namespace_v1.argo_events.metadata[0].name
#    annotations = { "eks.amazonaws.com/role-arn" : module.irsa_argo_events.iam_role_arn }
#  }

#  automount_service_account_token = true
#}

#resource "kubernetes_secret_v1" "event_sa" {
#  metadata {
#    name      = "${local.event_service_account}-secret"
#    namespace = kubernetes_namespace_v1.argo_events.metadata[0].name
#    annotations = {
#      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.event_sa.metadata[0].name
#      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.argo_events.metadata[0].name
#    }
#  }

#  type = "kubernetes.io/service-account-token"
#}

#module "irsa_argo_events" {
#  source = "aws-ia/eks-blueprints-addon/aws"
#  version               = "~> 1.0"
#  create_release = false
#  create_role = true
#  role_name      = "${local.name}-${local.event_namespace}"
#  role_policies = { policy2 = data.aws_iam_policy.sqs.arn }

#  oidc_providers = {
#    this = {
#      provider_arn    = module.eks.oidc_provider_arn
#      namespace       = local.event_namespace
#      service_account = local.event_service_account
#    }
#  }

#  tags = local.tags
#}


#------------------------------------------
# Amazon Prometheus
#------------------------------------------
locals {
  amp_ingest_service_account = "amp-iamproxy-ingest-service-account"
  amp_namespace              = "kube-prometheus-stack"
}

resource "aws_prometheus_workspace" "amp" {
  count = var.enable_amazon_prometheus ? 1 : 0

  alias = format("%s-%s", "amp-ws", local.name)
  tags  = local.tags
}

#---------------------------------------------------------------
# Grafana Admin credentials resources
#---------------------------------------------------------------
data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id  = aws_secretsmanager_secret.grafana.id
  depends_on = [aws_secretsmanager_secret_version.grafana]
}

resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "@_"
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

#---------------------------------------------------------------
# IRSA for Amazon Managed Prometheus
#---------------------------------------------------------------
module "amp_ingest_irsa" {
  count = var.enable_amazon_prometheus ? 1 : 0

  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.14"
  role_name = format("%s-%s", local.name, "amp-ingest")

  attach_amazon_managed_service_prometheus_policy  = true
  amazon_managed_service_prometheus_workspace_arns = [aws_prometheus_workspace.amp[0].arn]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.amp_namespace}:${local.amp_ingest_service_account}"]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# IAM Policy for FluentBit Add-on
#---------------------------------------------------------------
resource "aws_iam_policy" "fluentbit" {
  description = "IAM policy policy for FluentBit"
  name        = "${local.name}-fluentbit-additional"
  policy      = data.aws_iam_policy_document.fluent_bit.json
}

#---------------------------------------------------------------
# S3 log bucket for FluentBit
#---------------------------------------------------------------

#tfsec:ignore:*
module "fluentbit_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-fluentbit-"

  # For example only - please evaluate for your environment
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

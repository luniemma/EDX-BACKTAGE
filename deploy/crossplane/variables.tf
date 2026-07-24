variable "kube_context" {
  description = "kubeconfig context to target. Must be the local minikube cluster."
  type        = string
  default     = "minikube"
}

variable "kube_config_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "crossplane_version" {
  description = "Crossplane Helm chart version."
  type        = string
  default     = "2.3.4"
}

# ----- Cloud providers -----
# Installing a provider is free. Provisioning through it is not — see
# enable_*_provider_config below.

variable "install_aws_provider" {
  description = "Install the Crossplane AWS ECR provider."
  type        = bool
  default     = true
}

variable "install_azure_provider" {
  description = "Install the Crossplane Azure provider."
  type        = bool
  default     = false
}

# A ProviderConfig is what lets Crossplane actually create cloud resources and
# therefore actually spend money. Both default to false: the providers install
# and the XRD/Composition are usable in dry-run, but nothing reaches a cloud
# account until you deliberately turn this on and supply credentials.
variable "enable_aws_provider_config" {
  description = "Wire AWS credentials into Crossplane so it can provision real AWS resources."
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "Region for AWS resources created through Crossplane."
  type        = string
  default     = "us-east-1"
}

# Pass via environment, never a tfvars file:
#   export TF_VAR_aws_access_key_id=...
#   export TF_VAR_aws_secret_access_key=...
# Only read when enable_aws_provider_config is true.
variable "aws_access_key_id" {
  description = "AWS access key ID for Crossplane's ProviderConfig."
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_secret_access_key" {
  description = "AWS secret access key for Crossplane's ProviderConfig."
  type        = string
  sensitive   = true
  default     = ""
}

variable "install_xeta_apis" {
  description = "Install the migrated ObjectStore API from the Xeta AI Platform repo. Installing the API is free; creating a claim provisions a real S3 bucket."
  type        = bool
  default     = true
}

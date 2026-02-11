variable "project" {
  description = "The Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "The Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "billing_project" {
  description = "The Google Cloud billing project ID"
  type        = string
}

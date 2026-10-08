terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

variable "project_id" {
  description = "ID do projeto Google Cloud"
  type        = string
}

variable "region" {
  description = "Região padrão dos recursos"
  type        = string
  default     = "southamerica-east1"
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    "managed-by" = "terraform"
    purpose      = "estudo-gcp"
  }
}

resource "google_project_service" "pubsub" {
  project            = var.project_id
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

resource "google_pubsub_topic" "budget_alerts" {
  project = var.project_id
  name    = "budget-alerts"

  depends_on = [google_project_service.pubsub]
}
resource "google_service_account" "budget_guard" {
  project      = var.project_id
  account_id   = "budget-guard"
  display_name = "Budget guard - para VMs ao estourar o teto"
}

resource "google_project_iam_custom_role" "vm_stopper" {
  project = var.project_id
  role_id = "budgetGuardVmStopper"
  title   = "Budget Guard VM Stopper"
  permissions = [
    "compute.instances.list",
    "compute.instances.stop",
  ]
}

resource "google_project_iam_member" "guard_can_stop" {
  project = var.project_id
  role    = google_project_iam_custom_role.vm_stopper.id
  member  = "serviceAccount:${google_service_account.budget_guard.email}"
}
// ...existing code...

resource "google_project_service" "guard_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "eventarc.googleapis.com",
    "compute.googleapis.com",
    "storage.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "archive_file" "guard_src" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/guard.zip"
}

resource "google_storage_bucket" "guard_src" {
  name                        = "sek-estudo-matheus-guard-src"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket_object" "guard_src" {
  name   = "guard-${data.archive_file.guard_src.output_md5}.zip"
  bucket = google_storage_bucket.guard_src.name
  source = data.archive_file.guard_src.output_path
}

resource "google_cloudfunctions2_function" "guard" {
  project  = var.project_id
  name     = "budget-guard"
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "budget_guard"

    source {
      storage_source {
        bucket = google_storage_bucket.guard_src.name
        object = google_storage_bucket_object.guard_src.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    service_account_email = google_service_account.budget_guard.email

    environment_variables = {
      PROJECT_ID = var.project_id
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.budget_alerts.id
    retry_policy          = "RETRY_POLICY_DO_NOT_RETRY"
    service_account_email = google_service_account.budget_guard.email
  }

  depends_on = [
    google_project_service.guard_apis,
    google_project_iam_member.guard_can_invoke,
  ]
}

resource "google_project_iam_member" "guard_can_invoke" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.budget_guard.email}"
}
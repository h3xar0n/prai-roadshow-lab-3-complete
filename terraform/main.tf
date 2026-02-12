provider "google" {
  project               = var.project
  region                = var.region
  user_project_override = true
  billing_project       = var.billing_project
}

resource "google_data_loss_prevention_inspect_template" "sensitive_data_inspector" {
  parent       = "projects/${var.project}/locations/${var.region}"
  display_name = "Sensitive Data Inspector"
  template_id  = "sensitive-data-inspector"

  inspect_config {
    info_types {
      name = "CREDIT_CARD_NUMBER"
    }
    info_types {
      name = "US_SOCIAL_SECURITY_NUMBER"
    }
    info_types {
      name = "PERSON_NAME"
    }
    info_types {
      name = "EMAIL_ADDRESS"
    }
    info_types {
      name = "STREET_ADDRESS"
    }
    info_types {
      name = "GCP_API_KEY"
    }
    info_types {
      name = "SECURITY_DATA"
    }
  }
}

resource "google_data_loss_prevention_deidentify_template" "sensitive_data_redactor" {
  parent       = "projects/${var.project}/locations/${var.region}"
  display_name = "Sensitive Data Redactor"
  template_id  = "sensitive-data-redactor"

  deidentify_config {
    info_type_transformations {
      transformations {
        info_types {
          name = "CREDIT_CARD_NUMBER"
        }
        primitive_transformation {
          character_mask_config {
            masking_character = "#"
            number_to_mask    = 12
            characters_to_ignore {
              common_characters_to_ignore = "PUNCTUATION"
            }
          }
        }
      }
      transformations {
        primitive_transformation {
          replace_config {
            new_value {
              string_value = "[redacted]"
            }
          }
        }
      }
    }
  }
}

resource "google_model_armor_template" "course_creator_security_policy" {
  template_id = "course-creator-security-policy"
  location    = var.region
  project     = var.project

  labels = {
    "dev-tutorial" = "prod-ready-3"
  }

  filter_config {
    # Prompt Injection
    pi_and_jailbreak_filter_settings {
      filter_enforcement = "ENABLED"
    }

    # Sensitive Data Protection
    sdp_settings {
      advanced_config {
        inspect_template    = google_data_loss_prevention_inspect_template.sensitive_data_inspector.id
        deidentify_template = google_data_loss_prevention_deidentify_template.sensitive_data_redactor.id
      }
    }


    # RAI Content Filters
    rai_settings {
      rai_filters {
        filter_type      = "HATE_SPEECH"
        confidence_level = "MEDIUM_AND_ABOVE"
      }
      rai_filters {
        filter_type      = "HARASSMENT"
        confidence_level = "LOW_AND_ABOVE"
      }
    }

    # Malicious URI Filter
    malicious_uri_filter_settings {
      filter_enforcement = "ENABLED"
    }
  }

  template_metadata {
    log_template_operations = true
  }
}

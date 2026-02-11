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

  # Prompt Injection and Jailbreak
  pi_and_jailbreak_filter_config {
    filter_settings {
      filter_type      = "PROMPT_INJECTION"
      confidence_level = "LOW_AND_ABOVE"
    }
  }

  # Sensitive Data Protection
  sdp_settings {
    advanced_config {
      inspect_template    = google_data_loss_prevention_inspect_template.sensitive_data_inspector.name
      deidentify_template = google_data_loss_prevention_deidentify_template.sensitive_data_redactor.name
    }
  }

  # RAI Content Filters
  content_filter_config {
    filter_settings {
      label    = "HATE_SPEECH"
      severity = "MEDIUM_AND_ABOVE"
    }
    filter_settings {
      label    = "HARASSMENT"
      severity = "LOW_AND_ABOVE"
    }
  }

  # Malicious URL Filter
  malicious_url_filter_config {
    # Malicious URL filter enabled
    # enabled = true # Argument might be 'filter_enforcement' or 'enabled'. 
    # Search result said 'enabled'. I will try 'enabled'.
    enabled = true
  }

  # log_config omitted as it may not be supported in this resource version or struct.
}


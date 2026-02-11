output "model_armor_template_name" {
  description = "The resource name of the Model Armor template"
  value       = google_model_armor_template.course_creator_security_policy.name
}

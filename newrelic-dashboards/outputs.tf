output "dashboard_url" {
  description = "URL do dashboard no New Relic One."
  value       = newrelic_one_dashboard.oficina_mecanica.permalink
}

output "dashboard_guid" {
  description = "GUID do dashboard (útil para linkar de outros lugares, ex.: alertas)."
  value       = newrelic_one_dashboard.oficina_mecanica.guid
}

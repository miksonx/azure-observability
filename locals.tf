locals {
  common_tags = merge(
    {
      environment  = var.environment
      managed_by   = "terraform"
      project      = "centralized-observability"
      cost_center  = "platform-observability"
    },
    var.extra_tags
  )
}

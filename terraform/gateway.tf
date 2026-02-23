# BlackRoad Cloud — Gateway Terraform Module
# Deploys the BlackRoad Gateway to a Railway-like environment

terraform {
  required_version = ">= 1.5"
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 4.0" }
  }
}

variable "cloudflare_account_id" {
  default = "848cf0b18d51e0170e0d1537aec3505a"
}
variable "gateway_url" {
  description = "Backend gateway URL (Railway/Docker/Pi)"
  type        = string
}
variable "anthropic_api_key" {
  description = "Anthropic API key (stored in Vault, not state)"
  type        = string
  sensitive   = true
}
variable "openai_api_key" {
  description = "OpenAI API key (stored in Vault, not state)"
  type        = string
  sensitive   = true
}

# KV namespace for gateway cache
resource "cloudflare_workers_kv_namespace" "gateway_cache" {
  account_id = var.cloudflare_account_id
  title      = "blackroad-gateway-cache"
}

# Worker script
resource "cloudflare_worker_script" "gateway" {
  account_id = var.cloudflare_account_id
  name       = "blackroad-gateway"
  content    = file("${path.module}/../../workers/gateway/dist/index.js")

  plain_text_binding {
    name = "BLACKROAD_GATEWAY_URL"
    text = var.gateway_url
  }

  secret_text_binding {
    name = "BLACKROAD_ANTHROPIC_API_KEY"
    text = var.anthropic_api_key
  }

  secret_text_binding {
    name = "BLACKROAD_OPENAI_API_KEY"
    text = var.openai_api_key
  }

  kv_namespace_binding {
    name         = "CACHE"
    namespace_id = cloudflare_workers_kv_namespace.gateway_cache.id
  }
}

# Route: gateway.blackroad.ai
resource "cloudflare_worker_route" "gateway" {
  zone_id     = var.cloudflare_zone_id
  pattern     = "gateway.blackroad.ai/*"
  script_name = cloudflare_worker_script.gateway.name
}

output "gateway_worker_name" { value = cloudflare_worker_script.gateway.name }
output "gateway_url" { value = "https://gateway.blackroad.ai" }

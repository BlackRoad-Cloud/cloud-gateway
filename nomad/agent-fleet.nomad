# BlackRoad OS — Nomad Job: Agent Fleet
# Deploys the core 6 agents as containerized services on the fleet.

job "blackroad-agent-fleet" {
  datacenters = ["dc1"]
  type        = "service"
  namespace   = "blackroad"

  update {
    max_parallel      = 2
    min_healthy_time  = "15s"
    healthy_deadline  = "3m"
    progress_deadline = "10m"
    auto_revert       = true
    canary            = 1
  }

  group "gateway" {
    count = 1

    network {
      port "gateway" {
        static = 8787
        to     = 8787
      }
    }

    service {
      name = "blackroad-gateway"
      port = "gateway"

      check {
        type     = "http"
        path     = "/health"
        interval = "15s"
        timeout  = "5s"
      }

      tags = ["gateway", "ai", "proxy"]
    }

    task "gateway" {
      driver = "docker"

      config {
        image = "ghcr.io/blackroad-os-inc/blackroad-gateway:latest"
        ports = ["gateway"]
      }

      env {
        BLACKROAD_GATEWAY_BIND = "0.0.0.0"
        BLACKROAD_GATEWAY_PORT = "8787"
        NODE_ENV               = "production"
      }

      template {
        data = <<EOT
{{- with secret "kv/blackroad/providers" -}}
BLACKROAD_ANTHROPIC_API_KEY={{ .Data.data.anthropic_key }}
BLACKROAD_OPENAI_API_KEY={{ .Data.data.openai_key }}
BLACKROAD_OLLAMA_URL={{ .Data.data.ollama_url }}
{{- end -}}
EOT
        destination = "secrets/provider.env"
        env         = true
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }

  group "agents" {
    count = 6  # One instance per core agent

    scaling {
      enabled = true
      min     = 6
      max     = 30000

      policy {
        cooldown            = "5m"
        evaluation_interval = "30s"

        check "task_queue_depth" {
          source = "prometheus"
          query  = "blackroad_task_queue_depth"

          strategy "target-value" {
            target = 10  # Scale out when queue > 10 tasks per instance
          }
        }
      }
    }

    network {
      port "agent_api" { to = 3000 }
    }

    task "agent-runtime" {
      driver = "docker"

      config {
        image = "ghcr.io/blackroad-os/blackroad-agent-runtime:latest"
        ports = ["agent_api"]
      }

      env {
        BLACKROAD_GATEWAY_URL = "http://blackroad-gateway.service.consul:8787"
        NODE_ENV              = "production"
      }

      resources {
        cpu    = 256
        memory = 256
      }
    }
  }
}

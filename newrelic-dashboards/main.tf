# Dashboard exigido pela Fase 3 do Tech Challenge (PDF, seção "Monitoramento
# e Observabilidade"). Três páginas: a primeira cobre literalmente os três
# itens pedidos em "Expor dashboards com" (volume diário de OS, tempo médio
# de execução por status, erros e falhas); as outras duas cobrem o restante
# da seção "Monitorar" (latência, CPU/memória do Kubernetes, healthcheck).
#
# Todas as queries abaixo foram validadas contra a conta real via NerdGraph
# antes de escrever este arquivo (não são um chute de nomes de atributo) —
# ver comentário em cada widget para a fonte do dado.
resource "newrelic_one_dashboard" "oficina_mecanica" {
  name        = "Oficina Mecânica — Observabilidade (Fase 3)"
  permissions = "public_read_only"

  # --- Página 1: Ordens de Serviço (requisito literal do PDF) -------------
  # Dado de ServiceOrderCreated/ServiceOrderStatusChanged, eventos
  # customizados emitidos por app/shared/telemetry.py (oficina-mecanica-fiap,
  # ADR-0007) — a APM não sabe nada sobre esse domínio de negócio sozinha.
  page {
    name = "Ordens de Serviço"

    widget_billboard {
      title  = "Total de OS criadas (30 dias)"
      row    = 1
      column = 1
      width  = 3
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT count(*) FROM ServiceOrderCreated SINCE 30 days ago"
      }
    }

    # widget_line, não widget_bar: gráfico de barras no New Relic é pensado
    # pra comparação por FACET (uma barra por valor), não pra série temporal
    # — combinado com TIMESERIES ele não renderiza os buckets corretamente
    # (aparecia zerado mesmo com dado real por trás, confirmado via NerdGraph
    # rodando a mesma query fora do dashboard).
    widget_line {
      title  = "Volume diário de ordens de serviço"
      row    = 1
      column = 4
      width  = 9
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT count(*) FROM ServiceOrderCreated TIMESERIES 1 day SINCE 30 days ago"
      }
    }

    widget_bar {
      title  = "Tempo médio de execução por status (Diagnóstico, Execução, Finalização)"
      row    = 4
      column = 1
      width  = 6
      height = 4

      nrql_query {
        account_id = var.new_relic_account_id
        query      = <<-NRQL
          SELECT average(seconds_in_previous_status) AS 'segundos'
          FROM ServiceOrderStatusChanged
          WHERE from_status IN ('em_diagnostico', 'em_execucao', 'finalizada')
          FACET from_status
          SINCE 30 days ago
        NRQL
      }
    }

    # Janela curta (3h) + granularidade automática, não 30 dias/1 dia como o
    # widget anterior (bar chart, acima): esse é o painel pensado pro
    # requisito do PDF de "dashboard com análise ao vivo" durante a gravação
    # do vídeo — precisa reagir em minutos, não em dias. Com bucket diário,
    # qualquer teste feito no mesmo dia colapsa num único ponto por linha
    # (sem ponto anterior pra conectar, a linha não aparece — não é bug,
    # é falta de dado espalhado em dias diferentes, o que só existe depois
    # de uso real acumulado).
    widget_line {
      title  = "Tendência do tempo por status (últimas 3h, ao vivo)"
      row    = 4
      column = 7
      width  = 6
      height = 4

      nrql_query {
        account_id = var.new_relic_account_id
        query      = <<-NRQL
          SELECT average(seconds_in_previous_status)
          FROM ServiceOrderStatusChanged
          WHERE from_status IN ('em_diagnostico', 'em_execucao', 'finalizada')
          FACET from_status
          TIMESERIES
          SINCE 3 hours ago
        NRQL
      }
    }

    widget_table {
      title  = "Ordens rejeitadas (orçamento recusado pelo cliente)"
      row    = 8
      column = 1
      width  = 12
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = <<-NRQL
          SELECT order_id, seconds_in_previous_status AS 'segundos aguardando aprovacao'
          FROM ServiceOrderStatusChanged
          WHERE to_status = 'recusada'
          SINCE 30 days ago
        NRQL
      }
    }
  }

  # --- Página 2: APIs & Infraestrutura -------------------------------------
  # Dado de Transaction (APM, agente New Relic Python — oficina-mecanica-fiap)
  # e K8sContainerSample (New Relic Kubernetes integration, oficina-mecanica-
  # infra-kubernetes) — ver ADR-0007, itens 1 e 2.
  page {
    name = "APIs & Infraestrutura"

    widget_line {
      title  = "Latência média da API (ms)"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT average(duration) * 1000 FROM Transaction WHERE appName = '${var.app_name}' TIMESERIES SINCE 3 hours ago"
      }
    }

    widget_line {
      title  = "Throughput (requisições por minuto)"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT rate(count(*), 1 minute) FROM Transaction WHERE appName = '${var.app_name}' TIMESERIES SINCE 3 hours ago"
      }
    }

    widget_billboard {
      title  = "Uptime do healthcheck (/health)"
      row    = 4
      column = 1
      width  = 4
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT percentage(count(*), WHERE httpResponseCode < '400') AS 'uptime %' FROM Transaction WHERE appName = '${var.app_name}' AND request.uri = '/health' SINCE 1 day ago"
      }

      critical = 95
      warning  = 99
    }

    widget_line {
      title  = "CPU utilizada por pod (%)"
      row    = 4
      column = 5
      width  = 8
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT average(cpuCoresUtilization) FROM K8sContainerSample WHERE namespaceName = '${var.kubernetes_namespace}' AND containerName = '${var.api_container_name}' FACET podName TIMESERIES SINCE 3 hours ago"
      }
    }

    widget_line {
      title  = "Memória usada por pod (MB)"
      row    = 7
      column = 1
      width  = 12
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT average(memoryUsedBytes) / 1e6 FROM K8sContainerSample WHERE namespaceName = '${var.kubernetes_namespace}' AND containerName = '${var.api_container_name}' FACET podName TIMESERIES SINCE 3 hours ago"
      }
    }
  }

  # --- Página 3: Erros & Falhas nas Integrações ---------------------------
  # TransactionError vem da APM (app principal); AwsLambdaInvocation vem da
  # New Relic Lambda layer (oficina-mecanica-lambda-auth, ADR-0007, item 3) —
  # cobre as duas Lambdas (authenticate, authorizer) sem precisar de um
  # widget dedicado por função (facetado por `name`).
  page {
    name = "Erros & Falhas nas Integrações"

    widget_billboard {
      title  = "Taxa de erro da API"
      row    = 1
      column = 1
      width  = 4
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT percentage(count(*), WHERE error is true) AS 'taxa de erro %' FROM Transaction WHERE appName = '${var.app_name}' SINCE 1 day ago"
      }

      critical = 5
      warning  = 1
    }

    widget_line {
      title  = "Erros da API ao longo do tempo"
      row    = 1
      column = 5
      width  = 8
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT count(*) FROM TransactionError WHERE appName = '${var.app_name}' TIMESERIES SINCE 1 day ago"
      }
    }

    widget_table {
      title  = "Erros da API por tipo"
      row    = 4
      column = 1
      width  = 6
      height = 4

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT count(*) FROM TransactionError WHERE appName = '${var.app_name}' FACET error.class SINCE 1 day ago"
      }
    }

    widget_bar {
      title  = "Taxa de erro por Lambda (authenticate / authorizer)"
      row    = 4
      column = 7
      width  = 6
      height = 4

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT percentage(count(*), WHERE error is true) AS 'taxa de erro %' FROM AwsLambdaInvocation FACET name SINCE 1 day ago"
      }
    }

    widget_line {
      title  = "Erros nas Lambdas ao longo do tempo"
      row    = 8
      column = 1
      width  = 12
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "SELECT count(*) FROM AwsLambdaInvocation WHERE error is true FACET name TIMESERIES SINCE 1 day ago"
      }
    }
  }
}

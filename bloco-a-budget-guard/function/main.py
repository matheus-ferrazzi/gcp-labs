"""Budget guard: para todas as VMs do projeto quando o gasto REAL passa do teto.

Fluxo: Budget -> Pub/Sub (topico budget-alerts) -> esta funcao.
Equivalente AWS: AWS Budgets -> SNS -> Lambda -> ec2:StopInstances.
"""
import base64
import json
import os

import functions_framework
from google.cloud import compute_v1

PROJECT_ID = os.environ["PROJECT_ID"]


@functions_framework.cloud_event
def budget_guard(cloud_event):
    # 1) O Pub/Sub entrega a mensagem em base64 dentro do evento
    payload = json.loads(base64.b64decode(cloud_event.data["message"]["data"]))
    cost = payload.get("costAmount", 0)        # quanto ja gastou no mes
    budget = payload.get("budgetAmount", 0)    # o teto do budget

    # 2) Alertas de PREVISAO (forecast) nao derrubam nada: so gasto real
    if payload.get("alertThresholdExceeded") is None or cost < budget:
        print(f"OK: gasto {cost} de {budget}. Nada a fazer.")
        return

    # 3) Estourou: lista todas as VMs RUNNING do projeto (em todas as zonas)
    client = compute_v1.InstancesClient()
    request = compute_v1.AggregatedListInstancesRequest(
        project=PROJECT_ID, filter='status = "RUNNING"'
    )
    paradas = []
    for zone, scoped in client.aggregated_list(request=request):
        for vm in scoped.instances or []:
            zone_name = zone.split("/")[-1]
            client.stop(project=PROJECT_ID, zone=zone_name, instance=vm.name)
            paradas.append(f"{zone_name}/{vm.name}")

    print(f"TETO ESTOURADO: gasto {cost} >= {budget}. VMs paradas: {paradas or 'nenhuma'}")

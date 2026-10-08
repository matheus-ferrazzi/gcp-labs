# gcp-labs

Labs em Terraform do meu estudo de **Google Cloud**, feitos para a migração AWS/datacenter → GCP.
Cada lab traduz um padrão que eu já usava na AWS para o equivalente no GCP.

| Lab | Tema | Equivalente AWS |
|---|---|---|
| bloco-a-budget-guard | Budget → Pub/Sub → Cloud Run function que para VMs ao estourar o teto | Budgets → SNS → Lambda |

> Tudo roda num projeto sandbox com budget e é destruído no fim (`terraform destroy`).

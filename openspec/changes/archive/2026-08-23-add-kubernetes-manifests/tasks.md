## 1. Imagem da aplicação

- [x] 1.1 Buildar a imagem da aplicação a partir de `src/Dockerfile` com tag versionada (ex.: `fabricioveronez/kube-news-imersao:v1`)
- [x] 1.2 Publicar a imagem em um registry acessível pelo cluster de destino

## 2. Manifestos do banco de dados

- [x] 2.1 Criar `k8s/db-pvc.yaml` — `PersistentVolumeClaim` com `accessModes: ReadWriteOnce`
- [x] 2.2 Criar `k8s/db-deployment.yaml` — `Deployment` com 1 réplica, `strategy: Recreate`, imagem `postgres:16-bookworm`, env vars de credenciais e volume montado a partir da PVC
- [x] 2.3 Criar `k8s/db-service.yaml` — `Service` do tipo `ClusterIP` expondo a porta 5432

## 3. Manifestos da aplicação

- [x] 3.1 Criar `k8s/app-deployment.yaml` — `Deployment` com múltiplas réplicas, imagem versionada, env vars `DB_HOST/DB_PORT/DB_DATABASE/DB_USERNAME/DB_PASSWORD` apontando para o Service do banco, liveness probe em `GET /health` e readiness probe em `GET /ready`, e `resources` declarados
- [x] 3.2 Criar `k8s/app-service.yaml` — `Service` do tipo `LoadBalancer` expondo a porta 8080

## 4. Validação em cluster efêmero

- [x] 4.1 Subir um cluster `kind` efêmero
- [x] 4.2 Aplicar todos os manifestos (`kubectl apply -f k8s/`) e confirmar que todos os pods ficam `Running`/`Ready`
- [x] 4.3 Expor a aplicação localmente via `kubectl port-forward svc/app 8080:8080` (já que `kind` não provisiona `LoadBalancer` real)
- [x] 4.4 Exercitar o fluxo fim a fim: criar um post via UI/API e confirmar que persiste e é listado, validando a conexão da app com o banco pelo `Service` interno
- [x] 4.5 Reiniciar o pod do banco de dados e confirmar que os dados persistem (via PVC)
- [x] 4.6 Destruir o cluster `kind` de validação

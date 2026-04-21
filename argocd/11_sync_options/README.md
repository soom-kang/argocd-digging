# 11_sync_options

- 매칭 Git 경로: `github/11_sync_options`
- 목표: sync 실행 옵션(`PRUNE`, `DRY RUN`, `APPLY ONLY`, `FORCE`)과 주요 sync option, `replace`, `retry` 동작 이해

---

# 1. 옵션 맵 (UI/CLI/Manifest)

| 개념                        | CLI 플래그                 | Application 설정 예시                       | 설명                                                                                                                                                   |
| --------------------------- | -------------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| PRUNE                       | `--prune`                  | `automated.prune: true`                     | - Git에 더 이상 존재하지 않는 리소스를 클러스터에서 삭제<br>- live에만 존재하는 리소스를 `kubectl delete`로 제거                                       |
| DRY RUN                     | `--dry-run`                | (sync 실행 시점 옵션)                       | - 실제 변경 없이 적용 시뮬레이션<br>- validation + admission 체크만 수행 (rollout 전 사전 검증)                                                        |
| APPLY ONLY (OutOfSync only) | `--apply-out-of-sync-only` | `ApplyOutOfSyncOnly=true`                   | - 생성/업데이트만 수행, 삭제(prune) 절대 안함<br>- orphan 리소스는 그대로 유지                                                                         |
| FORCE                       | `--force`                  | 리소스 annotation `Force=true,Replace=true` | - immutable field 변경 등에서 강제 재생성<br>- 내부적으로 kubectl replace --force (delete + create)<br>- 다운타임 발생 가능 (리소스 recreate)          |
| Skip Schema Validation      | -                          | `Validate=false`                            | - Kubernetes schema validation 생략<br>- CRD가 아직 설치되지 않은 상태에서도 apply 허용                                                                |
| Auto-Create Namespace       | -                          | `CreateNamespace=true`                      | - 대상 namespace 없으면 자동 생성                                                                                                                      |
| Prune Last                  | -                          | `PruneLast=true`                            | - prune을 sync 마지막 단계에서 수행<br>- 대부분 production 환경에서 활성화                                                                             |
| Respect Ignore Differences  | -                          | `RespectIgnoreDifferences=true`             | - diff에서 무시한 필드 → apply 시에도 무시                                                                                                             |
| Server-Side Apply           | `--server-side`            | `ServerSideApply=true`                      | - field ownership을 kube-apiserver가 관리<br>- large manifest 처리 효율<br>- 기존 client-side apply와 field ownership 충돌 가능                        |
| Prune Propagation Policy    | -                          | `PrunePropagationPolicy=foreground`         | - foreground: 부모 삭제 → 자식 먼저 삭제 후 부모 삭제<br>- background(Default): 부모 삭제 → 자식은 GC가 비동기 삭제<br>- orphan: 부모 삭제 → 자식 유지 |
| Replace                     | `--replace`                | `Replace=true`                              | - apply 대신 replace 사용 (kubectl replace)<br>- apply merge 문제가 있는 경우                                                                          |
| Retry                       | `--retry-*`                | `syncPolicy.retry`                          | - sync 실패 시 재시도<br>- transient error 대응 (webhook, CRD race 등)                                                                                 |

---

# 2. Step 1. Application 생성

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f argocd/11_sync_options/application_setup.yaml
```

`application_setup.yaml`에는 아래 옵션이 기본 포함되어 있습니다.

- `Validate=false`
- `CreateNamespace=true`
- `PruneLast=true`
- `ApplyOutOfSyncOnly=true`
- `RespectIgnoreDifferences=true`
- `ServerSideApply=true`
- `PrunePropagationPolicy=foreground`
- `retry(limit/backoff/refresh)`

---

# 3. Step 2. DRY RUN 확인

```bash
argocd app sync study-sync-options --dry-run --argocd-context "$ARGOCD_CLI_CONTEXT"
argocd app get study-sync-options --argocd-context "$ARGOCD_CLI_CONTEXT"
```

검증 포인트:

1. 클러스터 실제 변경 없이 preview만 수행
2. 이후 실제 sync 전 영향 범위 확인 가능

---

# 4. Step 3. 최초 Sync + Auto-Create Namespace 확인

```bash
argocd app sync study-sync-options --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" get namespace study-sync-options
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-sync-options get deploy,svc,cm,job
```

검증 포인트:

1. `CreateNamespace=true`로 namespace가 자동 생성됨
2. `github/11_sync_options` 리소스가 정상 배포됨

---

# 5. Step 4. APPLY ONLY + Respect Ignore Differences 확인

`application_setup.yaml`에 `ignoreDifferences(/spec/replicas)`가 설정되어 있습니다.

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-sync-options scale deploy/sync-options-nginx --replicas=5
argocd app get study-sync-options --argocd-context "$ARGOCD_CLI_CONTEXT"

argocd app sync study-sync-options --apply-out-of-sync-only --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-sync-options get deploy sync-options-nginx -o jsonpath='{.spec.replicas}'; echo
```

검증 포인트:

1. `ApplyOutOfSyncOnly`로 변경된 리소스만 sync 대상이 됨
2. `RespectIgnoreDifferences=true`로 `replicas`(ignore 필드)는 sync 시 강제로 되돌리지 않음

---

# 6. Step 5. PRUNE + PrunePropagationPolicy 확인

먼저 `application_setup.yaml`의 `PrunePropagationPolicy` 값을 바꿔 동작 방식을 비교합니다.

```yaml
spec:
  syncPolicy:
    syncOptions:
      - PrunePropagationPolicy=foreground # background / orphan 으로 변경해 비교
```

값 변경 후 다시 apply:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f argocd/11_sync_options/application_setup.yaml
```

의미:

- `foreground`: 자식 삭제 완료 후 부모 삭제 (기본값)
- `background`: 부모 삭제 요청 후 GC가 비동기 처리
- `orphan`: 자식 orphan으로 남김

다음으로 prune를 검증합니다.

1. `github/11_sync_options/prune-candidate.yaml` 파일을 Git에서 삭제하고 push
2. sync를 `--prune` 없이 실행하여 리소스가 남는지 확인
3. `--prune`로 재실행하여 삭제 확인

```bash
argocd app sync study-sync-options --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-sync-options get cm sync-options-prune-candidate

argocd app sync study-sync-options --prune --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-sync-options get cm sync-options-prune-candidate
```

---

# 7. Step 6. FORCE + Replace 확인

## 6-1. FORCE (job 재실행 케이스)

`github/11_sync_options/rerun-job.yaml`은 리소스 annotation으로 `Force=true,Replace=true`를 사용합니다.

```bash
argocd app sync study-sync-options --force \
  --resource batch:Job:study-sync-options/sync-options-rerun-job \
  --argocd-context "$ARGOCD_CLI_CONTEXT"

kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-sync-options get job sync-options-rerun-job
```

## 6-2. Replace (immutable 리소스 갱신 케이스)

`github/11_sync_options/immutable-configmap.yaml`의 `data.VERSION`를 변경 후 push 했다고 가정합니다.

```bash
argocd app sync study-sync-options --argocd-context "$ARGOCD_CLI_CONTEXT"
# immutable 변경으로 실패 시
argocd app sync study-sync-options --replace --argocd-context "$ARGOCD_CLI_CONTEXT"
```

운영 주의:

- `--force`, `--replace`, `Force=true`, `Replace=true`는 재생성/삭제를 유발할 수 있어 다운타임 위험이 있음

---

# 8. Step 7. Retry 확인

CLI에서 sync retry를 직접 제어할 수 있습니다.

```bash
argocd app sync study-sync-options \
  --retry-limit 3 \
  --retry-backoff-duration 5s \
  --retry-backoff-factor 2 \
  --retry-backoff-max-duration 1m \
  --argocd-context "$ARGOCD_CLI_CONTEXT"
```

그리고 `application_setup.yaml`에는 기본 retry 정책도 포함되어 있습니다.

```yaml
spec:
  syncPolicy:
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 1m
      refresh: true
```

---

# 9. Step 8. 정리 (삭제)

```bash
argocd app delete study-sync-options --cascade --yes --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" delete namespace study-sync-options --ignore-not-found
```

---

# 운영 요약

- `dry-run`으로 영향 범위를 먼저 확인
- `apply-out-of-sync-only`로 대규모 앱 API 부하를 낮춤
- `prune`/`replace`/`force`는 삭제/재생성 위험을 인지하고 운영 창구(승인/점검 시간)에서 수행
- `retry`는 일시 장애 복구에 유용하지만 영구 오류는 해결하지 못하므로 원인 분석이 우선

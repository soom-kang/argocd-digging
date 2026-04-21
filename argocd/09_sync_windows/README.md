# 09_sync_windows

- 매칭 Git 경로: `github/09_sync_windows`
- 목표: AppProject `syncWindows`로 동기화 허용 시간대를 제어하는 동작 검증

---

# 1. Sync Window 의미

Sync Window는 특정 시간대에 Application sync를 허용/차단하는 정책입니다.

주요 사용 시나리오:

1. 업무시간 외 자동 배포 차단
2. 점검 시간대에만 수동 배포 허용
3. 운영 안정 구간에서 예외 없는 배포 통제

---

# 2. application_setup.yaml 핵심 옵션

```yaml
spec:
  syncWindows:
    - kind: deny
      schedule: "* * * * *"
      duration: 24h
      applications:
        - study-sync-window-app
      manualSync: false
```

의미:

- `deny`: 차단 규칙
- `schedule: "* * * * *" + duration: 24h`: 사실상 항상 차단 상태
- `manualSync: false`: 수동 sync도 차단

---

## Step 1. Project + Application 생성

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f argocd/09_sync_windows/application_setup.yaml
```

## Step 2. 수동 Sync 차단 확인

```bash
argocd app sync study-sync-window-app --argocd-context "$ARGOCD_CLI_CONTEXT"
argocd app get study-sync-window-app --argocd-context "$ARGOCD_CLI_CONTEXT"
```

기대 결과:

- sync 요청이 `sync window` 정책으로 거절됨

## Step 3. 수동 Sync 허용으로 변경 후 재검증

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" patch appproject study-sync-window \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/syncWindows/0/manualSync","value":true}]'

argocd app sync study-sync-window-app --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-sync-window get deploy,svc
```

검증 포인트:

1. `manualSync=false`에서는 수동 sync도 차단
2. `manualSync=true`로 변경하면 수동 sync는 허용

---

## Step 4. 정리 (삭제)

```bash
argocd app delete study-sync-window-app --cascade --yes --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" delete appproject study-sync-window --ignore-not-found
kubectl --kubeconfig "$STUDY_KUBECONFIG" delete namespace study-sync-window --ignore-not-found
```

---

# 운영 시 주의점

- `deny` 규칙이 넓으면 긴급 장애 복구 배포까지 막을 수 있음
- 운영에서는 예외 처리 정책(긴급 시 manualSync 허용 여부)을 사전에 정의해야 함

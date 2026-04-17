# 3_sync_waves_and_hooks

- 매칭 Git 경로: `github/3_sync_waves_and_hooks`
- 목표: hook + sync wave 실행 순서 검증

## Step 1. Application 생성 (yaml 파일 적용)

```bash
awk -v repo="$REPO_URL" '{gsub(/\$\{REPO_URL\}/,repo)}1' argocd/3_sync_waves_and_hooks/argo_setup.yaml \
  | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -
```

## Step 2. Sync 실행

```bash
argocd app sync study-waves-hooks --argocd-context "$ARGOCD_CLI_CONTEXT"
```

## Step 3. Hook/순서 확인

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-waves-hooks get jobs,pods
argocd app history study-waves-hooks --argocd-context "$ARGOCD_CLI_CONTEXT"
```

검증 포인트:

1. `PreSync` Job(`waves-hooks-presync-check`)이 먼저 실행
2. wave 0 ConfigMap 생성 후 wave 1 Deployment 반영
3. HookSucceeded 정책으로 Job은 성공 후 정리

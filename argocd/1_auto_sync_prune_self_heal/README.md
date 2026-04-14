# 1_auto_sync_prune_self_heal

- 매칭 Git 경로: `github/1_auto_sync_prune_self_heal`
- 목표: auto sync, prune, self-heal 검증

## Step 1. Application 생성 (자동 동기화 활성화)

```bash
cat <<EOF | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: study-auto-sync
spec:
  project: study
  source:
    repoURL: ${REPO_URL}
    targetRevision: main
    path: github/1_auto_sync_prune_self_heal
  destination:
    server: https://kubernetes.default.svc
    namespace: study-auto-sync
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
EOF
```

## Step 2. 최초 동기화 확인

```bash
argocd app get study-auto-sync --argocd-context "$ARGOCD_CLI_CONTEXT"
```

## Step 3. Self-Heal 테스트

클러스터에서 직접 드리프트를 만들고 자동 복구를 확인합니다.

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-auto-sync scale deploy/auto-sync-nginx --replicas=5
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-auto-sync get deploy auto-sync-nginx -w
```

잠시 후 replicas가 Git 기준값(2)로 복구되면 성공입니다.

## Step 4. Prune 테스트

`github/1_auto_sync_prune_self_heal/configmap.yaml` 파일을 Git에서 삭제 후 push 합니다.

```bash
argocd app get study-auto-sync --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-auto-sync get configmap
```

삭제한 ConfigMap이 클러스터에서도 제거되면 prune 검증이 완료됩니다.

# 10_orphaned_resources_monitoring

- 매칭 Git 경로: `github/10_orphaned_resources_monitoring`
- 목표: AppProject `orphanedResources` 옵션으로 비관리 리소스 감지를 경고로 확인

---

# 1. Orphaned Resource 의미

Orphaned Resource는 "현재 App이 관리하지 않지만, 대상 namespace에 존재하는 리소스"입니다.

실무에서 주로 발생하는 경우:

1. 긴급 대응으로 수동 생성한 리소스
2. 과거 배포 잔재
3. 다른 툴이 생성했지만 GitOps 범위에 포함되지 않은 리소스

`orphanedResources.warn: true`를 켜면 이런 리소스를 경고로 노출할 수 있습니다.

---

# 2. application_setup.yaml 핵심 옵션

```yaml
spec:
  orphanedResources:
    warn: true
```

추가로 기본 생성되는 `kube-root-ca.crt`는 실습 노이즈를 줄이기 위해 ignore 처리했습니다.

---

## Step 1. Project + Application 생성

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f argocd/10_orphaned_resources_monitoring/application_setup.yaml

argocd app sync study-orphan-monitor-app --argocd-context "$ARGOCD_CLI_CONTEXT"
```

## Step 2. 관리 대상 외 리소스 생성 (의도적 orphan)

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-orphan-monitor create configmap manual-orphan \
  --from-literal=owner=manual
```

## Step 3. 경고 확인

```bash
argocd app get study-orphan-monitor-app --argocd-context "$ARGOCD_CLI_CONTEXT"
argocd app resources study-orphan-monitor-app --orphaned --argocd-context "$ARGOCD_CLI_CONTEXT"
```

검증 포인트:

1. App 상태 정보에서 orphaned resource 경고 확인
2. `manual-orphan` 리소스가 orphan 목록에 표시

## Step 4. orphan 제거 후 정상화 확인

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-orphan-monitor delete configmap manual-orphan
argocd app get study-orphan-monitor-app --argocd-context "$ARGOCD_CLI_CONTEXT"
```

---

## Step 5. 정리 (삭제)

```bash
argocd app delete study-orphan-monitor-app --cascade --yes --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" delete appproject study-orphan-monitor --ignore-not-found
kubectl --kubeconfig "$STUDY_KUBECONFIG" delete namespace study-orphan-monitor --ignore-not-found
```

---

# 운영 시 주의점

- warn 모드는 감지만 수행하고 자동 삭제하지 않음
- 운영에서는 orphan 발견 시 조치 기준(삭제/편입/무시)을 팀 규칙으로 명확히 두는 것이 중요함

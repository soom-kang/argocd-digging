# 8_applicationset_list_generator

- 매칭 Git 경로: `github/8_applicationset_list_generator/apps/*`
- 목표: ApplicationSet List Generator로 여러 Application을 선언적으로 생성/유지하는 방식 검증

---

# 1. ApplicationSet 의미

`ApplicationSet`은 "Application을 자동으로 만들어내는 상위 리소스"입니다.

이 실습에서는 `list` generator를 사용해 다음 2개 App을 생성합니다.

- `study-team-a` -> `apps/team-a`
- `study-team-b` -> `apps/team-b`

핵심 효과:

1. App 수가 늘어도 템플릿 1개로 관리
2. 팀/환경별 경로만 데이터(elements)로 추가
3. 중복된 Application YAML 복사/수정 작업 감소

---

# 2. application_setup.yaml 핵심 옵션

```yaml
spec:
  generators:
    - list:
        elements:
          - appName: team-a
            path: github/8_applicationset_list_generator/apps/team-a
```

```yaml
template:
  metadata:
    name: "study-{{appName}}"
```

의미:

- `elements` 데이터가 템플릿 변수로 주입됨
- 각 element마다 별도 Application이 생성됨

---

## Step 1. ApplicationSet 생성

```bash
awk -v repo="$REPO_URL" '{gsub(/\$\{REPO_URL\}/,repo)}1' argocd/8_applicationset_list_generator/application_setup.yaml \
  | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -
```

## Step 2. 생성된 Application 확인

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" get applicationset
argocd app list --argocd-context "$ARGOCD_CLI_CONTEXT" | grep '^study-team-'
```

## Step 3. Sync 및 리소스 확인

```bash
argocd app sync study-team-a --argocd-context "$ARGOCD_CLI_CONTEXT"
argocd app sync study-team-b --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-appset-team-a get deploy,svc
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-appset-team-b get deploy,svc
```

검증 포인트:

1. `ApplicationSet` 1개로 `study-team-a`, `study-team-b` 두 App이 생성됨
2. 각 App이 서로 다른 path/namespace를 배포함

---

# 3. 확장 테스트 (선택)

`elements`에 team-c를 추가한 뒤 재적용하면,
새 Application이 자동으로 생성되는지 확인할 수 있습니다.

---

# 운영 시 주의점

- generator 데이터 변경이 곧 App 생성/삭제로 이어지므로, PR 리뷰 기준을 엄격히 두는 것이 좋음
- App 이름 규칙(`study-{{appName}}`)을 초기에 표준화해야 운영 중 충돌을 줄일 수 있음

# 02_auto_sync_prune_self_heal

- 매칭 Git 경로: `github/02_auto_sync_prune_self_heal`
- 목표: auto sync, prune, self-heal 검증
- `prune`: 불필요 리소스 제거
- `selfHeal`: 드리프트 자동 복구

---

# prune (리소스 삭제)

## 개념

Git에 없는 리소스를 클러스터에서 삭제
즉:

> "Git 기준으로 존재하지 않는 것은 제거"

## 동작 예시

상태

- Git:

```
Deployment A
```

- 클러스터:

```
Deployment A
Deployment B  ← 과거에 있었지만 Git에서 삭제됨
```

### prune=false

- B는 그대로 남음 (드리프트 발생)

### prune=true

- B 자동 삭제

## 중요한 특징

- **Garbage Collection 역할**
- GitOps에서 매우 중요한 정합성 유지 기능
- 잘못 쓰면 리소스 유실 가능

## 운영 관점 리스크

| 리스크           | 설명                             |
| ---------------- | -------------------------------- |
| 의도치 않은 삭제 | Git에서 실수로 삭제 시 바로 반영 |
| 수동 리소스      | kubectl로 만든 리소스 제거됨     |
| CRD 영향         | 일부 CR 제거 시 영향 큼          |

## 권장 전략

- Dev: `prune=true` OK
- Prod:
  - 초기: `false`
  - 안정화 후: `true` 점진 적용

---

# selfHeal (드리프트 자동 복구)

## 개념

**클러스터에서 수동 변경된 리소스를 Git 상태로 되돌림**

## 동작 예시

### 상태

- Git:

```
replicas: 3
```

- 클러스터 (누군가 kubectl로 변경):

```
replicas: 5
```

### selfHeal=false

- 그대로 유지 (drift 상태)

### selfHeal=true

- 자동으로 3으로 되돌림

## 핵심 의미

> "클러스터에서의 변경은 허용하지 않겠다"

## 동작 조건

self-heal은 아래 조건에서 작동:

- 자동 동기화(`automated`) 활성화 필요
- live state ≠ desired state

## 운영 리스크

| 리스크              | 설명                              |
| ------------------- | --------------------------------- |
| 수동 핫픽스 무력화  | 긴급 patch 적용해도 다시 롤백됨   |
| autoscaler 충돌     | HPA가 replicas 변경 → 다시 되돌림 |
| controller conflict | 다른 controller와 충돌 가능       |

## 권장 전략

- Git-only 운영이면: `true`
- mixed 운영이면: `false`

---

# prune vs selfHeal 비교

| 항목   | prune           | selfHeal            |
| ------ | --------------- | ------------------- |
| 대상   | **없는 리소스** | **변경된 리소스**   |
| 역할   | 삭제            | 복구                |
| 트리거 | Git에서 삭제됨  | 클러스터에서 변경됨 |
| 위험   | 리소스 삭제     | 수동 변경 무효화    |

# 함께 사용할 때 의미

```yaml
automated:
  prune: true
  selfHeal: true
```

이 조합은 사실상:

> **"Git 상태를 100% 강제"**
> 즉:

- 없는 건 삭제 (prune)
- 바뀐 건 되돌림 (self-heal)
  → 완전한 GitOps enforcement

---

## Step 1. Application 생성 (자동 동기화 + yaml 파일 적용)

```bash
awk -v repo="$REPO_URL" '{gsub(/\$\{REPO_URL\}/,repo)}1' argocd/02_auto_sync_prune_self_heal/argo_setup.yaml \
  | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -

# or
kstudy apply -f ./application_setup.yaml
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

`github/02_auto_sync_prune_self_heal/configmap.yaml` 파일을 Git에서 삭제 후 push 합니다.

```bash
argocd app get study-auto-sync --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-auto-sync get configmap
```

삭제한 ConfigMap이 클러스터에서도 제거되면 prune 검증이 완료됩니다.

## Step 5. 정리 (삭제)

```bash
argocd app delete study-auto-sync --cascade --yes --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" delete namespace study-auto-sync --ignore-not-found
```

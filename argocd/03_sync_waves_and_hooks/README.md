# 03_sync_waves_and_hooks

- 매칭 Git 경로: `github/03_sync_waves_and_hooks`
- 목표: hook + sync wave 실행 순서 검증

---

# 1. Sync Wave — 리소스 적용 순서 제어

## 핵심 개념

**Sync Wave는 “리소스 간 적용 순서”를 숫자로 정의하는 방식**입니다.

- Annotation:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"
```

- 기본값: `0`
- 음수 가능 (예: `-1`, `-2`)
- 낮은 값 → 먼저 적용

## 실행 순서

Argo CD는 다음 순서로 리소스를 적용합니다:

1. Sync Wave 값 기준 정렬
2. 같은 wave 내에서는 kind ordering (CRD → Namespace → 일반 리소스 등)
3. 병렬 적용

## 예시 구조

```yaml
# Wave -1: CRD
sync-wave: "-1"

# Wave 0: DB
sync-wave: "0"

# Wave 1: Backend
sync-wave: "1"

# Wave 2: Frontend
sync-wave: "2"
```

## 언제 쓰는가

- CRD → CR 순서 보장
- DB → API → UI 순차 배포
- 의존성 있는 서비스 간 안정적 rollout

---

# 2. Hook — 특정 타이밍에 실행되는 작업

## 핵심 개념

**Hook은 “특정 lifecycle 시점에 실행되는 Kubernetes 리소스(Job 등)”입니다.**

- Annotation:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
```

## Hook 종류

| Hook Type | 실행 시점    |
| --------- | ------------ |
| PreSync   | sync 시작 전 |
| Sync      | sync 중      |
| PostSync  | sync 완료 후 |
| SyncFail  | sync 실패 시 |
| Skip      | apply 제외   |

## 예시: DB Migration

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate-db
  annotations:
    argocd.argoproj.io/hook: PreSync
```

→ 앱 배포 전에 DB migration 수행

## Hook 삭제 정책

Hook은 기본적으로 남아있기 때문에, 보통 cleanup 설정을 같이 씁니다:

```yaml
annotations:
  argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

옵션:

- `HookSucceeded`
- `HookFailed`
- `BeforeHookCreation`

---

# 3. Sync Wave vs Hook — 차이점

| 항목      | Sync Wave            | Hook                     |
| --------- | -------------------- | ------------------------ |
| 목적      | 리소스 순서 제어     | 특정 시점 작업 실행      |
| 대상      | 모든 리소스          | 주로 Job                 |
| 실행 방식 | declarative ordering | lifecycle event 기반     |
| 실패 영향 | 일부 영향            | 전체 sync 실패 유발 가능 |

# 4. 같이 사용하는 패턴 (중요)

실무에서는 둘을 조합합니다.

## 패턴: Migration + 서비스 배포

```yaml
# PreSync Hook + Wave -1
DB Migration Job

# Wave 0
Database

# Wave 1
Backend

# Wave 2
Frontend
```

### 실행 흐름

1. PreSync Hook 실행 (migration)
2. Wave -1 → 0 → 1 → 2 순서 적용

# 5. 실무에서 자주 발생하는 문제

## 1) Hook 실패 → 전체 Sync 실패

- PreSync 실패 시 앱 배포 안 됨
- retry 전략 필요

## 2) Wave만으로는 부족한 경우

- "apply 전에 실행" → Hook 필요
- Wave는 apply 순서만 제어

## 3) Hook idempotency 문제

- Job이 재실행될 수 있음
- 반드시 **idempotent 설계** 필요

# 6. 설계 가이드 (중요)

## Sync Wave 설계

- -1: CRD / Infra
- 0: Core dependency (DB, Queue)
- 1: Backend
- 2: Frontend

## Hook 설계

- PreSync: migration, validation
- PostSync: smoke test, notification
- SyncFail: rollback or alert

---

# presync-job.yaml 이해

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: waves-hooks-presync-check
  namespace: study-waves-hooks
  annotations:
    argocd.argoproj.io/hook: PreSync # Sync 시작 전에 실행되는 Hook - 애플리케이션 리소스가 apply되기 전에 실행됨 - 실패 시 전체 Sync 중단
    argocd.argoproj.io/hook-delete-policy: HookSucceeded # 성공하면 자동 삭제 - 성공: 삭제됨 (클러스터 깨끗 유지) - 실패: 남음 (디버깅 가능)
    argocd.argoproj.io/sync-wave: "-1" # 가장 먼저 실행되는 그룹 - 일반 리소스 (wave 0)보다 먼저 실행 - 여러 PreSync Hook이 있다면 그 중에서도 먼저 실행됨
spec:
  backoffLimit: 0 # 재시도 없음 - 한 번 실패하면 즉시 Sync 실패 - 매우 강한 “fail-fast” 전략
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: precheck
          image: busybox:1.36
          command:
            [
              "sh",
              "-c",
              "echo '[PreSync] validation start'; sleep 3; echo '[PreSync] validation done'",
            ]
```

---

## Step 1. Application 생성 (yaml 파일 적용)

```bash
awk -v repo="$REPO_URL" '{gsub(/\$\{REPO_URL\}/,repo)}1' argocd/03_sync_waves_and_hooks/argo_setup.yaml \
  | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -

# or
kstudy apply -f ./application_setup.yaml
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

## Step 4. 정리 (삭제)

```bash
argocd app delete study-waves-hooks --cascade --yes --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" delete namespace study-waves-hooks --ignore-not-found
```

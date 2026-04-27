# 13_argo_rollouts_blue_green

- 매칭 Git 경로: `github/13_argo_rollouts_blue_green`
- 목표: Argo Rollouts와 Rollouts 플러그인/확장을 사용해 Argo CD 배포에 Blue/Green 전략 적용

---

# 1. 이번 강의에서 다루는 플러그인/확장

이번 실습은 Kubernetes 기본 `Deployment` 대신 Argo Rollouts의 `Rollout` CRD를 사용합니다.

역할을 정확히 구분하면 아래와 같습니다.

| 구성 요소 | 역할 |
| --- | --- |
| Argo Rollouts Controller | `Rollout` CRD를 감시하고 ReplicaSet, Service selector, promotion/abort를 제어 |
| `kubectl argo rollouts` plugin | Rollout 상태 조회, promote, abort, retry, dashboard 실행을 위한 CLI 플러그인 |
| Argo CD Rollout UI Extension | Argo CD Web UI에서 Rollout 리소스를 시각화하는 UI 확장 |

중요한 점:

- Blue/Green 트래픽 전환 자체는 Argo Rollouts Controller가 수행합니다.
- CLI 플러그인은 배포 상태 확인과 수동 promotion/abort를 위해 사용합니다.
- Argo CD UI Extension은 Argo CD 화면에서 Rollout 진행 상태를 보기 위한 보조 도구입니다.
- GitOps 원칙상 새 버전 배포는 `kubectl argo rollouts set image`로 직접 바꾸지 않고 Git의 `rollout.yaml`을 변경한 뒤 Argo CD sync로 반영합니다.

공식 문서:

- Argo Rollouts 소개: https://argoproj.github.io/argo-rollouts/
- Argo Rollouts 설치: https://argoproj.github.io/argo-rollouts/installation/
- Blue/Green 전략: https://argoproj.github.io/argo-rollouts/features/bluegreen/
- Kubectl plugin: https://argoproj.github.io/argo-rollouts/features/kubectl-plugin/
- Argo CD Rollout UI Extension: https://github.com/argoproj-labs/rollout-extension
- Argo CD Extension Installer: https://github.com/argoproj-labs/argocd-extension-installer

---

# 2. 이번 실습 구조

```text
argocd/13_argo_rollouts_blue_green/
├── application_setup.yaml
├── rollout_extension_patch.yaml
├── rollout_extension_cleanup_patch.yaml
└── README.md

github/13_argo_rollouts_blue_green/
├── namespace.yaml
├── service-active.yaml
├── service-preview.yaml
└── rollout.yaml
```

리소스 역할:

- `Rollout/rollouts-bluegreen`: Blue/Green 전략을 가진 애플리케이션
- `Service/rollouts-bluegreen-active`: 실제 사용자 트래픽이 들어가는 stable 서비스
- `Service/rollouts-bluegreen-preview`: 새 버전을 검증하는 preview 서비스
- `Application/study-rollouts-blue-green`: 위 Git 경로를 Argo CD로 배포
- `rollout_extension_patch.yaml`: Argo CD server에 Rollout UI Extension initContainer 추가

---

# 3. Blue/Green 동작 방식

`github/13_argo_rollouts_blue_green/rollout.yaml`의 핵심은 아래 설정입니다.

```yaml
strategy:
  blueGreen:
    activeService: rollouts-bluegreen-active
    previewService: rollouts-bluegreen-preview
    autoPromotionEnabled: false
    previewReplicaCount: 1
    scaleDownDelaySeconds: 30
```

의미:

| 필드 | 설명 |
| --- | --- |
| `activeService` | 운영 트래픽을 받는 Service |
| `previewService` | 새 버전을 먼저 연결해 검증하는 Service |
| `autoPromotionEnabled: false` | 새 버전이 준비되어도 자동 전환하지 않고 사람이 승인할 때까지 대기 |
| `previewReplicaCount: 1` | 검증 단계에서는 새 버전 Pod를 1개만 띄워 리소스 절약 |
| `scaleDownDelaySeconds: 30` | 전환 후 이전 ReplicaSet을 30초 동안 유지해 네트워크 전파 지연 완화 |

배포 흐름:

1. 최초 배포 시 `blue` 이미지가 active/preview 양쪽에 연결됩니다.
2. Git에서 이미지를 `green`으로 바꾸고 Argo CD sync를 실행합니다.
3. Argo Rollouts가 새 ReplicaSet을 만들고 preview Service만 새 버전으로 연결합니다.
4. active Service는 기존 `blue` 버전을 계속 바라봅니다.
5. preview 검증이 끝나면 `kubectl argo rollouts promote`로 수동 승인합니다.
6. active Service selector가 새 ReplicaSet hash로 전환됩니다.
7. 이전 ReplicaSet은 `scaleDownDelaySeconds` 이후 축소됩니다.

---

# 4. 사전 준비

기존 `argocd/00_argocd_setup.md`를 완료한 상태를 기준으로 합니다.

```bash
export STUDY_KUBECONFIG="$HOME/.kube/config-kind-argocd-study"
export ARGOCD_NS="argocd-study"
export ARGOCD_CLI_CONTEXT="argocd-study-local"
```

Argo CD CLI 로그인도 완료되어 있어야 합니다.

```bash
argocd app list --argocd-context "$ARGOCD_CLI_CONTEXT"
```

---

# 5. Step 1. Argo Rollouts Controller 설치

`Rollout`은 Kubernetes 기본 리소스가 아니므로 CRD와 controller를 먼저 설치합니다.

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" create namespace argo-rollouts \
  --dry-run=client -o yaml | kubectl --kubeconfig "$STUDY_KUBECONFIG" apply -f -

kubectl --kubeconfig "$STUDY_KUBECONFIG" apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

kubectl --kubeconfig "$STUDY_KUBECONFIG" -n argo-rollouts rollout status \
  deployment/argo-rollouts --timeout=300s
```

CRD 확인:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" get crd rollouts.argoproj.io
```

여기서 `rollouts.argoproj.io`가 보이지 않으면 Argo CD sync 시 `no matches for kind "Rollout"` 오류가 발생합니다.

---

# 6. Step 2. Kubectl Argo Rollouts plugin 설치

macOS Homebrew를 사용할 수 있으면 아래 방식이 가장 단순합니다.

```bash
brew install argoproj/tap/kubectl-argo-rollouts
kubectl argo rollouts version
```

Homebrew를 쓰지 않는 경우 운영체제와 CPU 아키텍처에 맞는 바이너리를 받아 설치합니다.

```bash
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-darwin-amd64
chmod +x ./kubectl-argo-rollouts-darwin-amd64
sudo mv ./kubectl-argo-rollouts-darwin-amd64 /usr/local/bin/kubectl-argo-rollouts
kubectl argo rollouts version
```

Apple Silicon이면 release asset 이름에서 `darwin-amd64` 대신 `darwin-arm64`를 사용합니다.
Linux이면 `linux-amd64` 또는 `linux-arm64`를 사용합니다.

플러그인 설치가 끝나면 아래 명령들이 가능해집니다.

```bash
kubectl argo rollouts get rollout
kubectl argo rollouts promote
kubectl argo rollouts abort
kubectl argo rollouts dashboard
```

---

# 7. Step 3. Argo CD Rollout UI Extension 설치

Argo CD Web UI에서 Rollout 리소스를 보기 위해 `argocd-server`에 UI Extension을 설치합니다.

이번 실습은 `argoproj-labs/rollout-extension`의 `v0.3.7` extension tarball을 사용하고, `argocd-extension-installer:v0.0.8` initContainer로 `/tmp/extensions/`에 설치합니다.

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" patch deployment argocd-server \
  --type strategic \
  --patch-file argocd/13_argo_rollouts_blue_green/rollout_extension_patch.yaml

kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" rollout status \
  deployment/argocd-server --timeout=300s
```

initContainer 확인:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" get pod \
  -l app.kubernetes.io/name=argocd-server \
  -o jsonpath='{.items[0].spec.initContainers[*].name}'; echo
```

`rollout-extension`이 보이면 설치 패치가 반영된 상태입니다.

주의:

- `argocd-server` Pod가 재시작되므로 기존 port-forward가 끊길 수 있습니다.
- extension installer는 GitHub release URL에 접근해야 하므로 클러스터 네트워크에서 GitHub 다운로드가 가능해야 합니다.
- UI가 바로 보이지 않으면 브라우저 새로고침 또는 강력 새로고침을 수행합니다.

---

# 8. Step 4. Argo CD Application 생성

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply \
  -f argocd/13_argo_rollouts_blue_green/application_setup.yaml
```

핵심 설정:

```yaml
spec:
  source:
    path: github/13_argo_rollouts_blue_green
  syncPolicy:
    syncOptions:
      - SkipDryRunOnMissingResource=true
      - RespectIgnoreDifferences=true
  ignoreDifferences:
    - group: ""
      kind: Service
      jsonPointers:
        - /spec/selector/rollouts-pod-template-hash
```

`ignoreDifferences`가 중요한 이유:

- Blue/Green에서는 Rollouts controller가 active/preview Service selector에 `rollouts-pod-template-hash`를 주입합니다.
- 이 hash는 Git에 고정해서 관리하면 안 되는 runtime 값입니다.
- Argo CD가 이 필드를 되돌리면 Rollouts controller와 Argo CD가 Service selector를 서로 덮어쓰는 충돌이 생깁니다.
- `RespectIgnoreDifferences=true`는 ignore한 필드를 sync apply 단계에서도 보존하도록 합니다.

---

# 9. Step 5. 최초 Sync

```bash
argocd app sync study-rollouts-blue-green --argocd-context "$ARGOCD_CLI_CONTEXT"
argocd app get study-rollouts-blue-green --argocd-context "$ARGOCD_CLI_CONTEXT"
```

클러스터 리소스 확인:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-rollouts-blue-green get \
  rollout,replicaset,pod,service
```

Rollouts plugin으로 상태 확인:

```bash
kubectl argo rollouts get rollout rollouts-bluegreen \
  -n study-rollouts-blue-green \
  --kubeconfig "$STUDY_KUBECONFIG"
```

Service selector 확인:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-rollouts-blue-green get svc \
  rollouts-bluegreen-active rollouts-bluegreen-preview \
  -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{.spec.selector}{"\n"}{end}'
```

최초 배포 후에는 active/preview Service 모두 현재 stable ReplicaSet hash를 바라봅니다.

---

# 10. Step 6. Active와 Preview 접속 확인

active Service:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-rollouts-blue-green port-forward \
  svc/rollouts-bluegreen-active 18080:80
```

브라우저에서 확인:

```text
http://localhost:18080
```

다른 터미널에서 preview Service도 확인합니다.

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-rollouts-blue-green port-forward \
  svc/rollouts-bluegreen-preview 18081:80
```

브라우저에서 확인:

```text
http://localhost:18081
```

최초 배포 상태에서는 둘 다 `argoproj/rollouts-demo:blue` 버전을 보여야 합니다.

---

# 11. Step 7. 새 버전 배포 요청

GitOps 방식으로 새 버전을 배포합니다.
`github/13_argo_rollouts_blue_green/rollout.yaml`에서 이미지를 변경합니다.

```yaml
image: argoproj/rollouts-demo:green
```

변경사항을 Git에 commit/push한 뒤 Argo CD에서 refresh/sync합니다.

```bash
argocd app sync study-rollouts-blue-green --argocd-context "$ARGOCD_CLI_CONTEXT"
```

Rollout 진행 상황을 watch합니다.

```bash
kubectl argo rollouts get rollout rollouts-bluegreen \
  -n study-rollouts-blue-green \
  --kubeconfig "$STUDY_KUBECONFIG" \
  --watch
```

기대 상태:

- 새 ReplicaSet이 생성됩니다.
- preview Service는 `green` 버전 ReplicaSet으로 전환됩니다.
- active Service는 기존 `blue` 버전을 계속 바라봅니다.
- `autoPromotionEnabled: false` 때문에 promotion 직전에서 일시정지됩니다.

이 상태는 실패가 아니라 의도된 승인 대기 상태입니다.
Argo CD UI나 Rollouts plugin에서 `Paused` 또는 promotion 대기 상태로 보일 수 있습니다.

---

# 12. Step 8. Preview 검증

Service selector를 다시 확인합니다.

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-rollouts-blue-green get svc \
  rollouts-bluegreen-active rollouts-bluegreen-preview \
  -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{.spec.selector}{"\n"}{end}'
```

검증 포인트:

- `rollouts-bluegreen-active`는 이전 hash를 바라봅니다.
- `rollouts-bluegreen-preview`는 새 hash를 바라봅니다.
- active URL은 기존 `blue` 화면입니다.
- preview URL은 새 `green` 화면입니다.

이때 운영 트래픽은 아직 새 버전으로 이동하지 않았습니다.
preview Service로 smoke test, QA, synthetic test를 수행한 뒤 승인 여부를 결정합니다.

---

# 13. Step 9. 수동 Promote

preview 검증이 성공하면 CLI 플러그인으로 수동 승인합니다.

```bash
kubectl argo rollouts promote rollouts-bluegreen \
  -n study-rollouts-blue-green \
  --kubeconfig "$STUDY_KUBECONFIG"
```

완료 상태 확인:

```bash
kubectl argo rollouts status --timeout 120s rollouts-bluegreen \
  -n study-rollouts-blue-green \
  --kubeconfig "$STUDY_KUBECONFIG"
```

다시 selector를 확인합니다.

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-rollouts-blue-green get svc \
  rollouts-bluegreen-active rollouts-bluegreen-preview \
  -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{.spec.selector}{"\n"}{end}'
```

promote 후에는 active/preview Service가 모두 새 ReplicaSet hash를 바라보게 됩니다.
기존 ReplicaSet은 `scaleDownDelaySeconds: 30` 때문에 일정 시간 유지된 뒤 축소됩니다.

---

# 14. Step 10. Abort와 GitOps rollback

preview 검증에서 문제가 발견되면 promotion 전에 abort할 수 있습니다.

```bash
kubectl argo rollouts abort rollouts-bluegreen \
  -n study-rollouts-blue-green \
  --kubeconfig "$STUDY_KUBECONFIG"
```

단, Git에는 여전히 `green` 이미지가 desired state로 남아 있습니다.
GitOps 환경에서 완전한 rollback은 Git을 되돌리는 방식으로 수행해야 합니다.

예시 흐름:

1. `github/13_argo_rollouts_blue_green/rollout.yaml`의 이미지를 다시 `argoproj/rollouts-demo:blue`로 변경
2. commit/push
3. Argo CD refresh/sync
4. Rollouts 상태 확인

운영 원칙:

- `kubectl argo rollouts abort`: 현재 진행 중인 rollout을 중단하는 runtime 조작
- Git revert: Argo CD desired state를 이전 버전으로 되돌리는 GitOps 조작
- 둘 중 하나만 수행하면 Argo CD와 live cluster 상태가 다시 벌어질 수 있습니다.

---

# 15. Step 11. Argo CD UI Extension 확인

Argo CD Web UI에서 아래 순서로 확인합니다.

1. `study-rollouts-blue-green` Application 선택
2. 리소스 트리에서 `Rollout/rollouts-bluegreen` 선택
3. Rollout Extension 패널에서 ReplicaSet, Pod, promotion 상태 확인

UI Extension이 보이지 않으면 아래를 확인합니다.

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" logs deployment/argocd-server \
  -c rollout-extension --tail=100
```

자주 보는 원인:

- `argocd-server` Pod가 아직 재시작 중
- initContainer가 extension tarball을 다운로드하지 못함
- 브라우저 캐시 때문에 이전 UI bundle이 보임
- Argo CD server port-forward가 재시작 후 끊김

---

# 16. Step 12. Rollouts Dashboard 실행

CLI 플러그인은 별도 로컬 dashboard도 제공합니다.

```bash
kubectl argo rollouts dashboard \
  -n study-rollouts-blue-green \
  --kubeconfig "$STUDY_KUBECONFIG" \
  --port 3100
```

브라우저에서 확인:

```text
http://localhost:3100/rollouts
```

Argo CD UI Extension과 Rollouts Dashboard의 차이:

| 도구 | 위치 | 용도 |
| --- | --- | --- |
| Argo CD UI Extension | Argo CD Web UI 내부 | GitOps Application 관점에서 Rollout 시각화 |
| Rollouts Dashboard | 로컬 CLI가 띄우는 웹 UI | 특정 namespace의 Rollout 진행 상태 디버깅 |

운영에서는 Argo CD UI Extension을 GitOps 흐름 관찰에 사용하고, CLI dashboard는 장애 대응이나 실습 디버깅에 사용하는 식으로 나누면 좋습니다.

---

# 17. 디버깅 명령

Application 상태:

```bash
argocd app get study-rollouts-blue-green --argocd-context "$ARGOCD_CLI_CONTEXT"
argocd app diff study-rollouts-blue-green --argocd-context "$ARGOCD_CLI_CONTEXT"
```

Rollout 상태:

```bash
kubectl argo rollouts get rollout rollouts-bluegreen \
  -n study-rollouts-blue-green \
  --kubeconfig "$STUDY_KUBECONFIG"

kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-rollouts-blue-green describe rollout rollouts-bluegreen
```

ReplicaSet/Pod 상태:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-rollouts-blue-green get rs,pod \
  -l app=rollouts-bluegreen
```

Service selector:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-rollouts-blue-green get svc \
  rollouts-bluegreen-active rollouts-bluegreen-preview -o yaml
```

Controller 로그:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n argo-rollouts logs deployment/argo-rollouts \
  --tail=100
```

UI Extension 설치 로그:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" logs deployment/argocd-server \
  -c rollout-extension --tail=100
```

---

# 18. 자주 발생하는 문제

| 증상 | 원인 | 조치 |
| --- | --- | --- |
| `no matches for kind "Rollout"` | Argo Rollouts CRD 미설치 | Step 1 controller 설치 확인 |
| Application이 계속 OutOfSync | Service selector hash를 Argo CD가 diff로 감지 | `ignoreDifferences`와 `RespectIgnoreDifferences=true` 확인 |
| preview만 green이고 active는 blue | 수동 promotion 대기 상태 | 검증 후 `kubectl argo rollouts promote` 실행 |
| promote 후에도 old pod가 잠시 남음 | `scaleDownDelaySeconds` 동작 | 30초 후 다시 확인 |
| UI Extension이 안 보임 | initContainer 실패 또는 브라우저 캐시 | `rollout-extension` 로그 확인 후 hard refresh |
| sync는 성공했지만 화면이 그대로임 | 기존 port-forward 연결 또는 브라우저 캐시 | port-forward 재시작, 새 탭에서 확인 |

---

# 19. 정리 (삭제)

Application 삭제:

```bash
argocd app delete study-rollouts-blue-green --cascade --yes --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" delete namespace study-rollouts-blue-green --ignore-not-found
```

Argo CD UI Extension 제거:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" patch deployment argocd-server \
  --type strategic \
  --patch-file argocd/13_argo_rollouts_blue_green/rollout_extension_cleanup_patch.yaml

kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" rollout status \
  deployment/argocd-server --timeout=300s
```

Argo Rollouts controller 제거는 다른 실습이나 애플리케이션에서 사용하지 않을 때만 수행합니다.

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" delete namespace argo-rollouts --ignore-not-found
kubectl --kubeconfig "$STUDY_KUBECONFIG" delete crd \
  rollouts.argoproj.io \
  analysisruns.argoproj.io \
  analysistemplates.argoproj.io \
  clusteranalysistemplates.argoproj.io \
  experiments.argoproj.io \
  --ignore-not-found
```

---

# 운영 요약

- Argo CD는 Git에 선언된 `Rollout`, `Service`를 배포합니다.
- Argo Rollouts controller는 rollout 진행 중 Service selector를 동적으로 바꿉니다.
- Service selector hash는 Git에 쓰지 말고 Argo CD `ignoreDifferences`로 제외합니다.
- `autoPromotionEnabled: false`를 사용하면 preview 검증 후 사람이 명시적으로 promote해야 합니다.
- CLI 플러그인은 `get`, `promote`, `abort`, `dashboard`에 유용하지만 이미지 변경은 Git으로 수행하는 것이 GitOps 흐름에 맞습니다.
- Argo CD UI Extension은 Argo CD 화면 안에서 Rollout 진행 상황을 이해하기 쉽게 보여주는 보조 도구입니다.

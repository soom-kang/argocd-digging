# 12_config_management_plugin

- 매칭 Git 경로: `github/12_config_management_plugin`
- 목표: Argo CD Config Management Plugin(CMP)이 repo-server sidecar로 매니페스트를 생성하는 방식 이해

---

# 1. Config Management Plugin 의미

Argo CD는 기본적으로 Helm, Kustomize, Jsonnet, plain directory를 지원합니다.
그 외 도구로 Kubernetes 매니페스트를 만들어야 하거나, 기본 도구의 기능만으로 부족한 경우 Config Management Plugin(CMP)을 사용합니다.

핵심 흐름은 아래와 같습니다.

1. `argocd-repo-server`가 Git 소스를 가져옴
2. Application이 `spec.source.plugin`을 사용하거나 plugin discovery rule에 매칭됨
3. repo-server가 소스 파일을 plugin sidecar로 전달함
4. plugin sidecar의 `generate` 명령이 YAML/JSON Kubernetes object stream을 stdout으로 출력함
5. Argo CD가 출력 결과를 일반 매니페스트처럼 diff/sync함

중요한 점:

- `ConfigManagementPlugin`은 Kubernetes CRD가 아니라 sidecar 내부 설정 파일입니다.
- 현재 권장 방식은 `argocd-repo-server`에 sidecar를 붙이는 방식입니다.
- 예전 `argocd-cm`의 `configManagementPlugins` 방식은 Argo CD v2.4부터 deprecated 되었고 v2.8부터 제거되었습니다.

참고 공식 문서:

- https://argo-cd.readthedocs.io/en/stable/operator-manual/config-management-plugins/

---

# 2. 이번 실습 구조

```text
argocd/12_config_management_plugin/
├── application_setup.yaml
├── plugin_configmap.yaml
├── repo_server_patch.yaml
├── repo_server_cleanup_patch.yaml
└── README.md

github/12_config_management_plugin/
└── plugin-input.env
```

역할:

- `plugin_configmap.yaml`: sidecar가 읽을 `ConfigManagementPlugin` 설정
- `repo_server_patch.yaml`: `argocd-repo-server`에 CMP sidecar 추가
- `application_setup.yaml`: CMP를 사용하는 Argo CD Application
- `plugin-input.env`: plugin이 읽어서 ConfigMap 매니페스트로 변환할 입력 파일

---

# 3. Step 1. CMP 설정 ConfigMap 생성

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply \
  -f argocd/12_config_management_plugin/plugin_configmap.yaml
```

핵심 설정:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ConfigManagementPlugin
metadata:
  name: study-cmp
spec:
  version: v1.0
  init:
    command: [sh, -c]
    args:
      - |
        test -f plugin-input.env
  generate:
    command: [sh, -c]
    args:
      - |
        ...
  discover:
    fileName: "./plugin-input.env"
```

의미:

- `metadata.name`: plugin 이름
- `spec.version`: plugin 버전, 명시 호출 시 이름은 `study-cmp-v1.0` 형식이 됨
- `init`: manifest 생성 직전에 실행되는 준비/검증 명령
- `generate`: 실제 Kubernetes YAML/JSON을 stdout으로 출력하는 명령
- `discover.fileName`: 해당 파일이 Application source path에 있으면 이 plugin 사용 가능

`generate`에서 stdout에는 오직 Kubernetes 매니페스트만 출력해야 합니다.
로그가 필요하면 stderr로 출력해야 하며, secret 같은 민감 정보가 UI에 노출되지 않도록 주의해야 합니다.

---

# 4. Step 2. argocd-repo-server에 sidecar 추가

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" patch deployment argocd-repo-server \
  --type strategic \
  --patch-file argocd/12_config_management_plugin/repo_server_patch.yaml

kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" rollout status deployment/argocd-repo-server --timeout=300s
```

sidecar 핵심 설정:

```yaml
containers:
  - name: study-cmp
    image: busybox:1.36.1
    command:
      - /var/run/argocd/argocd-cmp-server
    securityContext:
      runAsNonRoot: true
      runAsUser: 999
```

운영 포인트:

- entrypoint는 `/var/run/argocd/argocd-cmp-server`를 사용
- plugin 설정 파일은 `/home/argocd/cmp-server/config/plugin.yaml`에 위치
- sidecar는 `runAsUser: 999`로 실행
- `/tmp`는 repo-server와 공유하지 않고 별도 `emptyDir`를 사용

sidecar가 붙었는지 확인:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" get pod \
  -l app.kubernetes.io/name=argocd-repo-server \
  -o jsonpath='{.items[0].spec.containers[*].name}'; echo
```

`argocd-repo-server study-cmp`처럼 `study-cmp` 컨테이너가 보이면 준비 완료입니다.

---

# 5. Step 3. Application 생성

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply \
  -f argocd/12_config_management_plugin/application_setup.yaml
```

핵심 설정:

```yaml
spec:
  source:
    path: github/12_config_management_plugin
    plugin:
      env:
        - name: MESSAGE_SUFFIX
          value: from-application-plugin-env
```

의미:

- `plugin: {}` 또는 `plugin.env`가 있으면 CMP 경로로 manifest generation이 진행됨
- 이 실습에서는 plugin name을 직접 지정하지 않고 `discover.fileName`으로 자동 매칭
- Application의 plugin env는 plugin 내부에서 `ARGOCD_ENV_` prefix가 붙어 전달됨
- 위 `MESSAGE_SUFFIX`는 plugin 실행 시 `ARGOCD_ENV_MESSAGE_SUFFIX`로 읽힘

---

# 6. Step 4. Sync 및 결과 확인

```bash
argocd app sync study-cmp-plugin --argocd-context "$ARGOCD_CLI_CONTEXT"
argocd app get study-cmp-plugin --argocd-context "$ARGOCD_CLI_CONTEXT"

kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-cmp-plugin get cm cmp-generated-config -o yaml
```

검증 포인트:

1. `github/12_config_management_plugin/plugin-input.env`가 직접 apply되지 않음
2. CMP의 `generate` 명령이 `ConfigMap/cmp-generated-config`를 생성함
3. `data.message`에 Git 입력값과 Application plugin env 값이 함께 반영됨

예상 결과:

```yaml
data:
  color: blue
  generated-by: config-management-plugin
  message: hello-from-cmp-source from-application-plugin-env
```

---

# 7. Step 5. 변경 반영 테스트

`github/12_config_management_plugin/plugin-input.env`를 변경하고 Git에 push합니다.

예시:

```env
MESSAGE=hello-after-source-change
COLOR=green
```

그 다음 다시 sync합니다.

```bash
argocd app sync study-cmp-plugin --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-cmp-plugin get cm cmp-generated-config -o yaml
```

검증 포인트:

1. Argo CD는 Git 파일 변경을 OutOfSync로 감지
2. sync 시 CMP가 다시 실행됨
3. 생성된 ConfigMap data가 새 입력값으로 변경됨

Application env 변경도 테스트할 수 있습니다.

```yaml
spec:
  source:
    plugin:
      env:
        - name: MESSAGE_SUFFIX
          value: changed-from-application-env
```

Application을 재적용한 뒤 sync하면 `ARGOCD_ENV_MESSAGE_SUFFIX` 값이 바뀌어 결과 ConfigMap에 반영됩니다.

---

# 8. 디버깅 명령

매니페스트 생성 결과만 확인:

```bash
argocd app manifests study-cmp-plugin --argocd-context "$ARGOCD_CLI_CONTEXT"
```

Application 상태 확인:

```bash
argocd app get study-cmp-plugin --argocd-context "$ARGOCD_CLI_CONTEXT"
```

sidecar 로그 확인:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" logs deployment/argocd-repo-server \
  -c study-cmp --tail=100
```

자주 보는 실패 원인:

- `generate` stdout에 로그가 섞여 YAML 파싱 실패
- plugin 설정 파일이 `/home/argocd/cmp-server/config/plugin.yaml`에 mount되지 않음
- `plugin_configmap.yaml` 변경 후 repo-server Pod를 재시작하지 않아 이전 설정이 계속 사용됨
- sidecar entrypoint가 `/var/run/argocd/argocd-cmp-server`가 아님
- `discover.fileName`과 Application source path의 실제 파일명이 맞지 않음
- sidecar 이미지에 `generate` 명령이 요구하는 바이너리가 없음

---

# 9. Step 6. 정리 (삭제)

Application 삭제:

```bash
argocd app delete study-cmp-plugin --cascade --yes --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" delete namespace study-cmp-plugin --ignore-not-found
```

repo-server sidecar 제거:

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" patch deployment argocd-repo-server \
  --type strategic \
  --patch-file argocd/12_config_management_plugin/repo_server_cleanup_patch.yaml

kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" delete configmap study-cmp-plugin --ignore-not-found
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" rollout status deployment/argocd-repo-server --timeout=300s
```

---

# 운영 요약

- CMP는 Argo CD의 기본 렌더러가 아닌 도구를 연결할 때 사용
- plugin은 repo-server 권한 경계 안에서 실행되므로 신뢰 가능한 코드와 이미지만 사용
- `generate` stdout은 반드시 Kubernetes YAML/JSON만 출력
- 사용자 입력값은 shell command에 직접 붙이지 말고 escape/sanitize 필요
- monorepo에서는 plugin tar stream exclusion이나 `manifest-generate-paths` 최적화도 함께 검토

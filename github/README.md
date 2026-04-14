# Argo CD Feature Test Manifests

각 폴더는 Argo CD Application의 `spec.source.path`로 직접 연결해 테스트할 수 있도록 구성되어 있습니다.

## 폴더 목록

- `1_basic_sync`: 기본 동기화/상태 확인
- `1_auto_sync_prune_self_heal`: 자동 동기화 + prune + self-heal
- `1_sync_waves_and_hooks`: sync wave와 hook 순서 제어
- `1_ignore_differences`: 특정 필드 드리프트 무시
- `1_helm_chart`: Helm 소스 렌더링
- `1_kustomize_overlay`: Kustomize overlay 렌더링

각 기능에 대한 실행 가이드는 `argocd/` 폴더의 동일한 이름 문서를 참고하세요.

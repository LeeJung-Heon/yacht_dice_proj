# 컵퐁 3D와 컵 이미지

- 사용자의 요청: 컵퐁을 실제 3D로 새로 만들고 컵별 이미지를 선택할 수 있게 하며 예상 던지기 궤적을 없앤다.
- RealityKit으로 초록 테이블, 나무 테두리, 속이 열린 빨간 컵 열 개, 흰 공, 스튜디오 조명을 그린다. 컵의 규칙 좌표와 반지름을 3D 좌표로 바꾸므로 시각적 목표와 판정이 일치한다.
- 사진 보관함에서 컵 1~10의 사진을 각각 선택·교체·삭제한다. 축소·회전 보정·중앙 정사각형 자르기를 거쳐 컵 전면의 곡면에 입힌다. 편집 화면에서 3D 미리보기를 제공한다.
- 사용자는 온라인 상대에게도 공유하도록 확정했다. 로컬에서는 두 좌석에 같은 번호의 디자인을 적용하며 온라인에서는 각 좌석 소유자의 사진을 보여 준다. `cuppong_designs`에 512px JPEG 열 장을 저장하고 RLS가 본인·실제 컵퐁 상대의 읽기와 본인의 수정만 허용한다. 대전 로그와 승패에는 영향이 없다.
- 방에 들어가면 자신의 사진을 올리고 상대 사진을 받는다. 10초마다 버전만 확인해 바뀐 경우에만 다시 받으며, 실패하면 기본 컵 또는 이전 사진으로 게임을 계속하고 재시도 상태를 표시한다. 사진 삭제도 빈 디자인으로 공유한다.
- 예상 경로·착지점·정답을 알려 주는 조준 표시는 그리지 않는다. 실제 던진 공의 포물선 재생, 소리, 진동, 컵 소멸과 차례 처리는 유지한다.
- iOS 18+, Swift 6 strict concurrency. 외부 패키지를 추가하지 않는다.
- 사진 실패 시 기존 이미지를 보존하고 오류를 표시한다. 저장 성공 후에만 화면 상태를 바꾸며 재실행해도 유지한다.


구현 API 참고: [RealityKit MeshDescriptor](https://developer.apple.com/documentation/realitykit/meshdescriptor), [PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker), [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Apple 사진 데이터 선언](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype).

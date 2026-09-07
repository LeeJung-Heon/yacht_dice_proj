import Foundation

/// Supabase 프로젝트 `yacht-dice` (서울). publishable 키는 클라이언트에 두라고 만든 공개 키라 코드에 둔다.
/// 행 접근은 전부 RLS가 막는다.
enum SupabaseConfig {
    static let url = URL(string: "https://lkernselwouldtuialjh.supabase.co")!
    static let publishableKey = "sb_publishable_80ZwQTBJkaLTVFDfWO1Tmw_jKz2Q3eH"
}

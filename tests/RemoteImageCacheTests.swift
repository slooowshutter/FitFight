import Foundation

@main
struct RemoteImageCacheTests {
    static func main() {
        let first = URL(string: "https://example.supabase.co/storage/v1/object/sign/user-media/user/fight_post/photo?token=aaa")!
        let second = URL(string: "https://example.supabase.co/storage/v1/object/sign/user-media/user/fight_post/photo?token=bbb")!
        let other = URL(string: "https://example.supabase.co/storage/v1/object/sign/user-media/user/fight_post/other?token=aaa")!

        let firstKey = RemoteImageCache.key(for: first)
        precondition(
            firstKey == RemoteImageCache.key(for: second),
            "Signed URL tokens must not bust the photo cache"
        )
        precondition(
            firstKey != RemoteImageCache.key(for: other),
            "Different photos must keep different cache keys"
        )
        precondition(
            !firstKey.contains("token="),
            "Cache keys must drop the signed query string"
        )
        precondition(
            RemoteImageCache.fileName(for: firstKey) == RemoteImageCache.fileName(for: RemoteImageCache.key(for: second)),
            "Disk names must follow the token-free key"
        )
        precondition(
            RemoteImageCache.fileName(for: firstKey).count == 64,
            "Disk names must be a SHA-256 hex digest"
        )
    }
}

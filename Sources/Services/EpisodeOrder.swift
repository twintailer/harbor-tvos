import Foundation

enum EpisodeOrder {
    /// Addons may return unsorted or duplicated entries. Find the next distinct
    /// episode without relying on array indices or replaying a duplicate row.
    static func next(after current: MetaItem.Video, in videos: [MetaItem.Video]) -> MetaItem.Video? {
        guard let season = current.season, let episode = current.episode else { return nil }
        return videos.filter {
            guard let s = $0.season, let e = $0.episode, s > 0, e > 0 else { return false }
            return s > season || (s == season && e > episode)
        }.min {
            let left = ($0.season ?? 0, $0.episode ?? 0)
            let right = ($1.season ?? 0, $1.episode ?? 0)
            return left < right
        }
    }
}

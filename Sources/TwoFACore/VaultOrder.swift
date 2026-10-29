import Foundation

public enum VaultOrder {
    /// 未指定位置时使用文件中的顺序；相同位置用 UUID 保证排序稳定。
    public static func ordered(_ records: [VaultRecord]) -> [VaultRecord] {
        records.enumerated()
            .filter { $0.element.deletedAt == nil }
            .sorted { lhs, rhs in
                let left = lhs.element.sortOrder ?? lhs.offset
                let right = rhs.element.sortOrder ?? rhs.offset
                return left == right ? lhs.element.id.uuidString < rhs.element.id.uuidString : left < right
            }
            .map(\.element)
    }

    public static func nextOrder(_ records: [VaultRecord]) -> Int {
        let highest = records.enumerated().filter { $0.element.deletedAt == nil }
            .map { $0.element.sortOrder ?? $0.offset }.max() ?? -1
        return highest < Int.max ? highest + 1 : Int.max
    }

    /// 移动后统一编号，原子保存时可以一次提交全部变化。
    public static func moving(_ records: [VaultRecord], id: UUID, to target: UUID, at date: Date) -> [VaultRecord]? {
        var live = ordered(records)
        guard id != target,
              let sourceIndex = live.firstIndex(where: { $0.id == id }),
              let targetIndex = live.firstIndex(where: { $0.id == target }) else { return nil }
        let moved = live.remove(at: sourceIndex)
        live.insert(moved, at: targetIndex)
        let positions = Dictionary(uniqueKeysWithValues: live.enumerated().map { ($0.element.id, $0.offset) })
        return records.map { record in
            var record = record
            if let position = positions[record.id], record.sortOrder != position {
                record.sortOrder = position
                record.updatedAt = date
            }
            return record
        }
    }
}

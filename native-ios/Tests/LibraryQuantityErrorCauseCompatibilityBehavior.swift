import Foundation

@main
struct LibraryQuantityErrorCauseCompatibilityBehavior {
    static func main() {
        let legacyRecord: [String: Any] = [
            "subject": "数量关系",
            "errorCause": "边界遗漏、单位换算",
            "weaknessTags": ["单位换算", "读题不全", " 读题不全 "]
        ]
        precondition(
            LibraryQuantityErrorCauseCompatibility.values(in: legacyRecord)
                == ["边界遗漏", "单位换算", "读题不全"]
        )

        var editedRecord = legacyRecord
        editedRecord["cause"] = "旧别名错因"
        editedRecord["errorCause"] = "计算失误"
        LibraryQuantityErrorCauseCompatibility.markAuthoritative(in: &editedRecord)
        precondition(LibraryQuantityErrorCauseCompatibility.values(in: editedRecord) == ["计算失误"])

        editedRecord["errorCause"] = ""
        precondition(LibraryQuantityErrorCauseCompatibility.values(in: editedRecord).isEmpty)

        precondition(
            LibraryQuantityErrorCauseCompatibility.serialized(
                errorCause: "错因一、错因二",
                weaknessTags: ["错因二", "旧错因"],
                authoritative: false
            ) == "错因一、错因二、旧错因"
        )
        precondition(
            LibraryQuantityErrorCauseCompatibility.serialized(
                errorCause: "",
                weaknessTags: ["旧错因"],
                authoritative: true
            ).isEmpty
        )
    }
}

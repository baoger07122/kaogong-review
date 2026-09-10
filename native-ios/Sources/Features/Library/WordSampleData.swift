import Foundation

enum WordSampleData {
    static func samples(for category: WordCategory) -> [[String: Any]] {
        switch category {
        case .idiomDefinition:
            [
                ["name": "不一而足", "entryKind": "word", "pinyin": "bù yī ér zú", "meaning": "不止一种或一次，表示同类事物很多。", "example": "造成错误的原因不一而足。", "sentiment": "中性"],
                ["name": "深入浅出", "entryKind": "word", "pinyin": "shēn rù qiǎn chū", "meaning": "内容深刻而表达浅显易懂。", "example": "这本书讲解得深入浅出。", "sentiment": "褒义"]
            ]
        case .idiomComparison:
            [[
                "name": "不以为然 vs 不以为意",
                "commonMeaning": "都用于描述对事物的态度。",
                "judgmentHint": "根据语境判断是“不赞同”还是“不放在心上”。",
                "compareNote": "区分对观点的态度与对事情的重视程度。",
                "sentiment": "中性",
                "compareWords": [["name": "不以为然", "meaning": "不认为是对的", "entryKind": "word"], ["name": "不以为意", "meaning": "不放在心上", "entryKind": "word"]]
            ]]
        case .wordDefinition:
            [
                ["name": "贯彻", "entryKind": "word", "pos": "动词", "meaning": "彻底实现或体现方针、政策、精神等。", "example": "贯彻执行相关政策。", "sentiment": "中性"],
                ["name": "落实", "entryKind": "word", "pos": "动词", "meaning": "使计划或措施得以实现。", "example": "把任务落实到具体工作中。", "sentiment": "中性"]
            ]
        case .wordComparison:
            [[
                "name": "贯彻 vs 落实",
                "commonMeaning": "都表示执行或实现。",
                "judgmentHint": "根据宾语和落地程度判断使用哪一个词。",
                "compareNote": "贯彻强调彻底执行，落实强调使计划落地。",
                "sentiment": "中性",
                "compareWords": [["name": "贯彻", "meaning": "彻底执行", "entryKind": "word"], ["name": "落实", "meaning": "使计划落地", "entryKind": "word"]]
            ]]
        }
    }
}

import Foundation

@main
enum SpeedGrowthPresentationBehavior {
    static func main() {
        let currentFormat = SpeedGrowthPresentation.parse("基期 4754，增长率 24%，求增量")
        precondition(currentFormat.baseValue == "4754", "parses a current growth question base")
        precondition(currentFormat.growthRate == "24", "parses a current growth question rate")
        precondition(currentFormat.isStructured, "marks a recognized question as structured")

        let threeDigitBase = SpeedGrowthPresentation.parse("基期 804，增长率 7%，求增量")
        precondition(threeDigitBase.baseValue == "804", "parses a three-digit base")
        precondition(threeDigitBase.growthRate == "7", "parses a one-digit growth rate")

        let legacyFormat = SpeedGrowthPresentation.parse("基期：４，７５４；增长率 ２４％；求增量")
        precondition(legacyFormat.baseValue == "4,754", "normalizes full-width digits and retains grouping")
        precondition(legacyFormat.growthRate == "24", "normalizes a full-width growth rate")

        let unrecognized = "基期数据待核对，请按原题作答"
        let fallback = SpeedGrowthPresentation.parse(unrecognized)
        precondition(!fallback.isStructured, "keeps unrecognized historical expressions unstructured")
        precondition(fallback.fallbackExpression == unrecognized, "preserves the complete original expression")
    }
}

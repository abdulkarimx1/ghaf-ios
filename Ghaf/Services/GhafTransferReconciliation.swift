import Foundation
import SwiftData
import OSLog
import GhafCore

@MainActor
enum GhafTransferReconciliation {
    static func run(in context: ModelContext) throws -> (pairs: Int, review: Int) {
        let transactions = try context.fetch(FetchDescriptor<GhafTransaction>())
        var migrated = 0
        for item in transactions where item.category == "Utilities" && item.subcategory == "Transfer" {
            item.category = "Transfers"; item.subcategory = nil; migrated += 1
        }
        if migrated > 0 {
            Logger(subsystem: "Ghaf", category: "Transfers").info("Migrated \(migrated, privacy: .public) legacy Utilities transfers")
        }
        let accounts = try context.fetch(FetchDescriptor<GhafAccount>()).filter { !$0.isArchived }
        let accountIDs = Set(accounts.map(\.id))
        let ownNameKeys = Set((CategoryTaxonomy.transferSubcategories.first { $0.name == "Between my accounts" }.map { [$0.name, $0.arabic] + $0.words } ?? []).map(CategoryMatcher.normalize))
        var ownDecisions = 0
        for item in transactions where item.transferDecision == nil && item.subcategory.map({ ownNameKeys.contains(CategoryMatcher.normalize($0)) }) == true {
            item.transferDecision = "own"; ownDecisions += 1
        }
        let candidates = transactions.filter { $0.transferPairKey == nil && $0.transferDecision == nil }.map { item in
            let transferCategory = CategoryTaxonomy.category(named: item.category)?.kind == .transfer || item.category == "Transfers received"
            let unlabelledTransfer = item.category == "Other" && [item.merchant, item.note].compactMap { $0 }.contains { text in
                let normalized = CategoryMatcher.normalize(text)
                return ["transfer", "xfer", "between accounts", "تحويل"].contains { normalized.contains($0) }
            }
            return AccountTransferMatcher.Candidate(
                id: item.id, accountID: item.accountID.flatMap { accountIDs.contains($0) ? $0 : nil },
                amount: item.amount, currency: item.currency, date: item.date, direction: item.direction,
                isReversal: item.isReversal,
                hasTransferEvidence: item.category != "Adjustment" && (transferCategory || unlabelledTransfer
                    || item.category == "Transfers" || item.category == "Utilities" && CategoryMatcher.normalize(item.subcategory ?? "") == "transfer")
            )
        }
        let existing = Set(transactions.compactMap(\.transferPairKey))
        let pairs = AccountTransferMatcher.pairs(in: candidates, alreadyPaired: existing)
        let transferEvidenceIDs = Set(candidates.filter(\.hasTransferEvidence).map(\.id))
        var pairCount = 0
        for pair in pairs {
            guard let debit = transactions.first(where: { $0.id == pair.debitID }),
                  let credit = transactions.first(where: { $0.id == pair.creditID }) else { continue }
            for item in [debit, credit] { item.category = "Transfers"; item.subcategory = "Between my accounts"; item.transferDecision = "own"; item.transferPairKey = pair.key; item.needsReview = false }
            pairCount += 1
        }
        var categoriesUpdated = 0
        for item in transactions where transferEvidenceIDs.contains(item.id) && item.category == "Other" && !item.isReversal {
            item.category = "Transfers"; categoriesUpdated += 1
        }
        var reviewCount = 0
        let ownAccountNames = Set((CategoryTaxonomy.transferSubcategories.first { $0.name == "Between my accounts" }.map { [$0.name, $0.arabic] + $0.words } ?? []).map(CategoryMatcher.normalize))
        for item in transactions where item.direction == "debit" && item.transferDecision == nil && item.transferPairKey == nil && !item.isReversal
            && item.accountID.map(accountIDs.contains) == true
            && transferEvidenceIDs.contains(item.id)
            && !TransactionEffect.isKnownExternalTransferSubcategory(item.subcategory)
            && item.subcategory.map({ !ownAccountNames.contains(CategoryMatcher.normalize($0)) }) != false
            && item.date <= Date.now.addingTimeInterval(-3 * 86_400) {
            if !item.needsReview { item.needsReview = true; reviewCount += 1 }
        }
        if pairCount > 0 || reviewCount > 0 || migrated > 0 || categoriesUpdated > 0 || ownDecisions > 0 { try context.save() }
        return (pairCount, reviewCount)
    }
}

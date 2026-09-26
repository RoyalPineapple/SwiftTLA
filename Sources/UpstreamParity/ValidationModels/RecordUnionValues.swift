import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct RecordUnionSentinelModel {
    package enum Sentinel: String, CaseIterable, FiniteTLAValueDomain {
        case noBlock = "NoBlock"
        package static var defaultValue: Self { .noBlock }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package struct Block: Hashable, Sendable { package let account: String; package let balance: Int }
    package struct SignedBlock: Hashable, Sendable { package let block: Block; package let signature: String }
    package typealias Value = OneOf<SignedBlock, Sentinel>
    enum Step: String, CaseIterable { case create, advance, clear }

    package static var spec: TLASpec {
        #spec("RecordUnionSentinel") { scope in
            let value = scope.sharedVar(in: Set<Value>([
                Value.second(Sentinel.noBlock),
                Value.first(SignedBlock(block: Block(account: "NoBlock", balance: 0), signature: "NoBlock")),
                Value.first(SignedBlock(block: Block(account: "account", balance: 3), signature: "signature"))
            ]))
            Do(Step.create, when: value == Value.second(Sentinel.noBlock)) {
                Assign(value, to: Value.first(SignedBlock(
                    block: Block(account: "NoBlock", balance: 0), signature: "NoBlock")))
            }
            Do(Step.advance) {
                When(value != Value.second(Sentinel.noBlock))
                let signed = value.assuming(SignedBlock.self)
                When(signed.block.balance < 3)
                Assign(value, to: Value.first(SignedBlock.expression(
                    block: Block.expression(account: signed.block.account, balance: signed.block.balance + 1),
                    signature: signed.signature)))
            }
            Do(Step.clear, when: value != Value.second(Sentinel.noBlock)) {
                Assign(value, to: Value.second(Sentinel.noBlock))
            }
            Validation("Records and model-value sentinel") {}
        }
    }
}

@TLAModel
package struct RecordUnionOrderingModel {
    package struct First: Hashable, Sendable { package let a: Int; package let z: Int }
    package struct Second: Hashable, Sendable { package let a: Int; package let b: Int }
    package struct Third: Hashable, Sendable { package let a: [Int]; package let c: Bool }
    package typealias Tail = OneOf<Second, Third>
    package typealias Value = OneOf<First, Tail>
    enum Step: String, CaseIterable { case finish }

    package static var spec: TLASpec {
        #spec("RecordUnionOrdering") { scope in
            let value = scope.sharedVar(in: Set<Value>([
                Value.first(First(a: 2, z: 0)),
                Value.second(Tail.first(Second(a: 2, b: -1))),
                Value.second(Tail.second(Third(a: [1], c: true))),
                Value.first(First(a: 0, z: 2)),
                Value.second(Tail.first(Second(a: 1, b: 9))),
                Value.second(Tail.second(Third(a: [], c: false)))
            ]))
            Algorithm("SelectRecord") {
                Do(Step.finish) { Assign(value, to: value); Stop() }
            }
            Validation("All record alternatives") {}
        }
    }
}

@TLAModel
package struct RecordUnionFieldDomainModel {
    package struct Count: Hashable, Sendable { package let value: Int }
    package struct Flag: Hashable, Sendable { package let value: Bool }
    package typealias Value = OneOf<Count, Flag>
    enum Step: String, CaseIterable { case finish }

    package static var spec: TLASpec {
        #spec("RecordUnionFieldDomain") { scope in
            let value = scope.sharedVar(in: Set<Value>([
                Value.second(Flag(value: true)), Value.first(Count(value: 0)),
                Value.second(Flag(value: false)), Value.first(Count(value: -1))
            ]))
            Algorithm("SelectRecord") {
                Do(Step.finish) { Assign(value, to: value); Stop() }
            }
            Validation("All field domains") {}
        }
    }
}

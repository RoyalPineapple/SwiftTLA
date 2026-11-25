import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/MissionariesAndCannibals/MissionariesAndCannibals.tla.
@TLAModel
package struct MissionariesAndCannibalsModel: Sendable {
    package enum Person: String, CaseIterable, FiniteTLAValueDomain {
        case m1, m2, m3, c1, c2, c3
        case apM1 = "m1_OF_PERSON", apM2 = "m2_OF_PERSON", apM3 = "m3_OF_PERSON"
        case apC1 = "c1_OF_PERSON", apC2 = "c2_OF_PERSON", apC3 = "c3_OF_PERSON"

        package static var defaultValue: Self { .m1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue {
            switch self {
            case .m1, .m2, .m3, .c1, .c2, .c3: .constant(rawValue)
            case .apM1, .apM2, .apM3, .apC1, .apC2, .apC3: .string(rawValue)
            }
        }
    }

    package enum Bank: String, CaseIterable, TLAValueType {
        case E, W

        package static var defaultValue: Self { .E }
    }

    private enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("MissionariesAndCannibals") { scope in
            Extends(.integers, .finiteSets)
            let configuredPeople = Set<Set<Person>>([
                Set([.m1, .m2, .m3]), Set([.c1, .c2, .c3]),
                Set([.apM1, .apM2, .apM3]), Set([.apC1, .apC2, .apC3])
            ])
            let Missionaries = scope.parameter(as: Set<Person>.self, in: configuredPeople)
            let Cannibals = scope.parameter(as: Set<Person>.self, in: configuredPeople)
            let Banks = SetExpr<Bank>.literal(.E, .W)
            let People = Missionaries.union(Cannibals)
            let bank_of_boat = scope.sharedVar(initial: Bank.E)
            let who_is_on_bank = scope.sharedVar(initial:
                Dictionary<Bank, Set<Person>>.mapping(over: Banks) { bank in
                    If(bank == Bank.E, then: People, else: Set<Person>())
                })

            Do(Step.next) {
                With(Subsets(of: who_is_on_bank[bank_of_boat])) { passengers in
                    let other = If(bank_of_boat == Bank.E, then: Bank.W, else: Bank.E)
                    let departing = who_is_on_bank[bank_of_boat].subtracting(passengers)
                    let arriving = who_is_on_bank[other].union(passengers)
                    When(SetExpr<Int>.literal(1, 2).contains(passengers.expr.count))
                    When(departing.isSubset(of: Cannibals)
                        || departing.intersection(Cannibals).count
                            <= departing.intersection(Missionaries).count)
                    When(arriving.isSubset(of: Cannibals)
                        || arriving.intersection(Cannibals).count
                            <= arriving.intersection(Missionaries).count)
                    who_is_on_bank.set(
                        Dictionary<Bank, Set<Person>>.mapping(over: Banks) { bank in
                            If(bank == bank_of_boat, then: departing, else: arriving)
                        })
                    bank_of_boat.set(other)
                }
            }
            let typeOK = Invariant("TypeOK")
            typeOK {
                Banks.contains(bank_of_boat)
                    && Functions(from: Banks, to: Subsets(of: People)).contains(who_is_on_bank)
            }
            let solution = Invariant("Solution")
            solution { !who_is_on_bank[Bank.E].isEmpty }

            Validation("MissionariesAndCannibals") {
                Bind(Missionaries, to: Set<Person>([.m1, .m2, .m3]))
                Bind(Cannibals, to: Set<Person>([.c1, .c2, .c3]))
            }.checking(only: [typeOK, solution])
                .expect(solution, .violated)
            Validation("APMissionariesAndCannibals") {
                Bind(Missionaries, to: Set<Person>([.apM1, .apM2, .apM3]))
                Bind(Cannibals, to: Set<Person>([.apC1, .apC2, .apC3]))
            }.checking(only: [typeOK, solution])
                .expect(solution, .violated)
        }
    }
}

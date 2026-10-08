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

    private enum Step: String, CaseIterable { case Next }

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

            let TypeOK = Invariant()
            let Solution = Invariant()

            Do(Step.Next) {
                With(Subsets(of: who_is_on_bank[bank_of_boat])) { passengers in
                    let other = If(bank_of_boat == Bank.E, then: Bank.W, else: Bank.E)
                    let departing = who_is_on_bank[bank_of_boat].subtracting(passengers)
                    let arriving = who_is_on_bank[other].union(passengers)
                    When(SetExpr<Int>.literal(1, 2).contains(passengers.expr.cardinality))
                    When(departing.isSubset(of: Cannibals)
                        || departing.intersection(Cannibals).cardinality
                            <= departing.intersection(Missionaries).cardinality)
                    When(arriving.isSubset(of: Cannibals)
                        || arriving.intersection(Cannibals).cardinality
                            <= arriving.intersection(Missionaries).cardinality)
                    Assign(who_is_on_bank, to:
                        Dictionary<Bank, Set<Person>>.mapping(over: Banks) { bank in
                            If(bank == bank_of_boat, then: departing, else: arriving)
                        })
                    Assign(bank_of_boat, to: other)
                }
            }
            TypeOK {
                Banks.contains(bank_of_boat)
                    && Functions(from: Banks, to: Subsets(of: People)).contains(who_is_on_bank)
            }
            Solution { !who_is_on_bank[Bank.E].isEmpty }

            let MissionariesAndCannibals = Validation {
                Bind(Missionaries, to: Set<Person>([.m1, .m2, .m3]))
                Bind(Cannibals, to: Set<Person>([.c1, .c2, .c3]))
            }.checking(only: [TypeOK, Solution])
                .expect(Solution, .violated)
                .checkingMode(.decisiveCounterexample)
            MissionariesAndCannibals
            let APMissionariesAndCannibals = Validation {
                Bind(Missionaries, to: Set<Person>([.apM1, .apM2, .apM3]))
                Bind(Cannibals, to: Set<Person>([.apC1, .apC2, .apC3]))
            }.checking(only: [TypeOK, Solution])
                .expect(Solution, .violated)
                .checkingMode(.decisiveCounterexample)
            APMissionariesAndCannibals
        }
    }
}

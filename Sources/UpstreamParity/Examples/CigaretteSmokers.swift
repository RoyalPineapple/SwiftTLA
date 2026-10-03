import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/CigaretteSmokers/CigaretteSmokers.tla.
@TLAModel
package struct CigaretteSmokersModel: Sendable {
    package enum Ingredient: String, CaseIterable, FiniteTLAValueDomain {
        case matches, paper, tobacco
        case apMatches = "matches_OF_INGREDIENT"
        case apPaper = "paper_OF_INGREDIENT"
        case apTobacco = "tobacco_OF_INGREDIENT"

        package static var defaultValue: Self { .matches }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue {
            switch self {
            case .matches, .paper, .tobacco: .constant(rawValue)
            case .apMatches, .apPaper, .apTobacco: .string(rawValue)
            }
        }
    }

    package struct Smoker: Hashable, Sendable {
        package let smoking: Bool
    }

    package enum Step: String, CaseIterable { case startSmoking, stopSmoking }

    package static var spec: TLASpec {
        #spec("CigaretteSmokers") { scope in
            Extends(.integers, .finiteSets)
            let Ingredients = scope.parameter(as: Set<Ingredient>.self, in: Set<Set<Ingredient>>([
                Set<Ingredient>([.matches, .paper, .tobacco]),
                Set<Ingredient>([.apMatches, .apPaper, .apTobacco])
            ]))
            let Offers = scope.parameter(as: Set<Set<Ingredient>>.self,
                in: Set<Set<Set<Ingredient>>>([
                    Set<Set<Ingredient>>([
                        Set<Ingredient>([.matches, .paper]),
                        Set<Ingredient>([.matches, .tobacco]),
                        Set<Ingredient>([.paper, .tobacco])
                    ]),
                    Set<Set<Ingredient>>([
                        Set<Ingredient>([.apMatches, .apPaper]),
                        Set<Ingredient>([.apMatches, .apTobacco]),
                        Set<Ingredient>([.apPaper, .apTobacco])
                    ])
                ]))
            Assume(Offers.isSubset(of: Subsets(of: Ingredients))
                && ForAll(in: Offers) { offer in
                    offer.cardinality == Ingredients.cardinality - 1
                })

            let smokers = scope.sharedVar(initial: Dictionary<Ingredient, Smoker>.mapping(over: Ingredients) { _ in
                Smoker.expression(smoking: false)
            })
            let dealer = scope.sharedVar(in: Offers)
            let TypeOK = Invariant()
            let AtMostOne = Invariant()

            Do(Step.startSmoking) {
                When(!dealer.isEmpty)
                Assign(smokers, to: Dictionary<Ingredient, Smoker>.mapping(over: Ingredients) { ingredient in
                    Smoker.expression(smoking:
                        Set<Ingredient>([]).inserting(ingredient.expr).union(dealer) == Ingredients)
                })
                Assign(dealer, to: Set<Ingredient>([]))
            }
            Do(Step.stopSmoking) {
                When(dealer.isEmpty)
                Let(Select(from: Ingredients) { ingredient in
                    smokers[ingredient].smoking && ForAll(in: Ingredients) { other in
                        !smokers[other].smoking || other == ingredient
                    }
                }) { ingredient in
                    Assign(smokers[ingredient].smoking, to: false)
                }
                With(Offers) { offer in
                    Assign(dealer, to: offer)
                }
            }

            TypeOK {
                Functions(from: Ingredients, to: SetExpr<Smoker>.literal(
                    Smoker(smoking: false), Smoker(smoking: true))).contains(smokers)
                    && (Offers.contains(dealer) || dealer.isEmpty)
            }
            AtMostOne {
                Ingredients.filtering { ingredient in smokers[ingredient].smoking }.cardinality <= 1
            }

            let CigaretteSmokers = Validation {
                Bind(Ingredients, to: Set<Ingredient>([.matches, .paper, .tobacco]))
                Bind(Offers, to: Set<Set<Ingredient>>([
                    Set<Ingredient>([.matches, .paper]),
                    Set<Ingredient>([.matches, .tobacco]),
                    Set<Ingredient>([.paper, .tobacco])
                ]))
            }
            CigaretteSmokers
            let APCigaretteSmokers = Validation {
                Bind(Ingredients, to: Set<Ingredient>([.apMatches, .apPaper, .apTobacco]))
                Bind(Offers, to: Set<Set<Ingredient>>([
                    Set<Ingredient>([.apMatches, .apPaper]),
                    Set<Ingredient>([.apMatches, .apTobacco]),
                    Set<Ingredient>([.apPaper, .apTobacco])
                ]))
            }
            APCigaretteSmokers
        }
    }
}
